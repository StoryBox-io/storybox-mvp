defmodule StoryboxWeb.ApiController do
  use StoryboxWeb, :controller

  require Ash.Query

  def ping(conn, %{"story_id" => story_id}) do
    json(conn, %{status: "ok", story_id: story_id})
  end

  def synopsis_view(conn, _params) do
    story = conn.assigns.current_story

    latest =
      Storybox.Stories.SynopsisVersion
      |> Ash.Query.filter(story_id == ^story.id)
      |> Ash.Query.sort(version_number: :desc)
      |> Ash.Query.limit(1)
      |> Ash.read_one(authorize?: false)

    case latest do
      {:ok, nil} ->
        conn
        |> put_status(404)
        |> json(%{error: "no synopsis found"})

      {:ok, version} ->
        case Storybox.Storage.get_content(version.content_uri) do
          {:ok, content} ->
            json(conn, %{
              story_id: story.id,
              version_number: version.version_number,
              inserted_at: version.inserted_at,
              content: content
            })

          {:error, _} ->
            conn
            |> put_status(503)
            |> json(%{error: "content unavailable"})
        end

      {:error, _} ->
        conn
        |> put_status(500)
        |> json(%{error: "internal error"})
    end
  end

  def treatment_view(conn, _params) do
    story = conn.assigns.current_story

    pieces =
      Storybox.Stories.SequencePiece
      |> Ash.Query.filter(story_id == ^story.id)
      |> Ash.Query.sort(position: :asc)
      |> Ash.read!(authorize?: false)

    approved_ids =
      pieces
      |> Enum.map(& &1.approved_version_id)
      |> Enum.reject(&is_nil/1)

    versions_by_id =
      case approved_ids do
        [] ->
          %{}

        ids ->
          Storybox.Stories.SequenceVersion
          |> Ash.Query.filter(id in ^ids)
          |> Ash.read!(authorize?: false)
          |> Map.new(&{&1.id, &1})
      end

    acts =
      pieces
      |> Enum.group_by(& &1.act)
      |> Enum.sort_by(fn {act, _} -> {is_nil(act), act} end)
      |> Enum.map(fn {act, seqs} ->
        %{
          act: act,
          sequences:
            Enum.map(seqs, fn piece ->
              version = versions_by_id[piece.approved_version_id]

              %{
                id: piece.id,
                title: piece.title,
                position: piece.position,
                approved_version: format_version(version)
              }
            end)
        }
      end)

    json(conn, %{
      story_id: story.id,
      through_lines: story.through_lines,
      acts: acts
    })
  end

  def script_view(conn, params) do
    story = conn.assigns.current_story

    case parse_script_mode(params) do
      {:error, reason} ->
        conn |> put_status(400) |> json(%{error: reason})

      {:ok, mode, snapshot_id} ->
        sequences =
          Storybox.Stories.SequencePiece
          |> Ash.Query.filter(story_id == ^story.id)
          |> Ash.Query.sort(position: :asc)
          |> Ash.read!(authorize?: false)

        sequence_ids = Enum.map(sequences, & &1.id)

        scene_pieces =
          Storybox.Stories.ScenePiece
          |> Ash.Query.filter(sequence_piece_id in ^sequence_ids)
          |> Ash.Query.sort(position: :asc)
          |> Ash.read!(authorize?: false)

        scenes_by_sequence = Enum.group_by(scene_pieces, & &1.sequence_piece_id)
        scene_piece_ids = Enum.map(scene_pieces, & &1.id)

        case resolve_script_versions(mode, snapshot_id, story.id, scene_pieces, scene_piece_ids) do
          {:error, :snapshot_not_found} ->
            conn |> put_status(404) |> json(%{error: "snapshot not found"})

          {:ok, versions_map} ->
            case build_script_scenes(scene_pieces, versions_map) do
              {:error, :content_unavailable} ->
                conn |> put_status(503) |> json(%{error: "content unavailable"})

              {:ok, scenes_with_content} ->
                result =
                  sequences
                  |> Enum.map(fn seq ->
                    scenes =
                      scenes_by_sequence
                      |> Map.get(seq.id, [])
                      |> Enum.map(&scenes_with_content[&1.id])

                    %{
                      id: seq.id,
                      title: seq.title,
                      act: seq.act,
                      position: seq.position,
                      scenes: scenes
                    }
                  end)

                json(conn, %{
                  story_id: story.id,
                  mode: mode,
                  snapshot_id: snapshot_id,
                  sequences: result
                })
            end
        end
    end
  end

  defp parse_script_mode(%{"mode" => mode} = params)
       when mode in ["latest", "approved", "snapshot"] do
    if mode == "snapshot" do
      case params do
        %{"snapshot_id" => id} -> {:ok, mode, id}
        _ -> {:error, "snapshot_id is required when mode is snapshot"}
      end
    else
      {:ok, mode, nil}
    end
  end

  defp parse_script_mode(%{"mode" => _}),
    do: {:error, "mode must be latest, approved, or snapshot"}

  defp parse_script_mode(_), do: {:error, "mode is required"}

  defp resolve_script_versions("latest", _snapshot_id, _story_id, _scene_pieces, scene_piece_ids) do
    all_versions =
      Storybox.Stories.SceneVersion
      |> Ash.Query.filter(scene_piece_id in ^scene_piece_ids)
      |> Ash.read!(authorize?: false)

    versions_map =
      all_versions
      |> Enum.group_by(& &1.scene_piece_id)
      |> Map.new(fn {id, vs} -> {id, Enum.max_by(vs, & &1.version_number)} end)

    {:ok, versions_map}
  end

  defp resolve_script_versions(
         "approved",
         _snapshot_id,
         _story_id,
         scene_pieces,
         _scene_piece_ids
       ) do
    approved_ids =
      scene_pieces
      |> Enum.map(& &1.approved_version_id)
      |> Enum.reject(&is_nil/1)

    versions_by_id =
      case approved_ids do
        [] ->
          %{}

        ids ->
          Storybox.Stories.SceneVersion
          |> Ash.Query.filter(id in ^ids)
          |> Ash.read!(authorize?: false)
          |> Map.new(&{&1.id, &1})
      end

    versions_map =
      Map.new(scene_pieces, fn piece ->
        {piece.id, versions_by_id[piece.approved_version_id]}
      end)

    {:ok, versions_map}
  end

  defp resolve_script_versions("snapshot", snapshot_id, story_id, scene_pieces, _scene_piece_ids) do
    result =
      Storybox.Stories.ScriptSnapshot
      |> Ash.Query.filter(id == ^snapshot_id and story_id == ^story_id)
      |> Ash.read_one(authorize?: false)

    case result do
      {:ok, nil} ->
        {:error, :snapshot_not_found}

      {:ok, snapshot} ->
        version_ids = Map.values(snapshot.entries)

        versions_by_id =
          case version_ids do
            [] ->
              %{}

            ids ->
              Storybox.Stories.SceneVersion
              |> Ash.Query.filter(id in ^ids)
              |> Ash.read!(authorize?: false)
              |> Map.new(&{to_string(&1.id), &1})
          end

        versions_map =
          Map.new(scene_pieces, fn piece ->
            version_id = snapshot.entries[to_string(piece.id)]
            {piece.id, versions_by_id[version_id]}
          end)

        {:ok, versions_map}

      {:error, _} ->
        {:error, :snapshot_not_found}
    end
  end

  defp build_script_scenes(scene_pieces, versions_map) do
    Enum.reduce_while(scene_pieces, {:ok, %{}}, fn piece, {:ok, acc} ->
      version = versions_map[piece.id]

      case fetch_scene_content(version) do
        {:error, :content_unavailable} ->
          {:halt, {:error, :content_unavailable}}

        {:ok, content} ->
          scene = %{
            id: piece.id,
            title: piece.title,
            position: piece.position,
            version: format_version(version),
            content: content
          }

          {:cont, {:ok, Map.put(acc, piece.id, scene)}}
      end
    end)
  end

  defp fetch_scene_content(nil), do: {:ok, nil}

  defp fetch_scene_content(version) do
    case Storybox.Storage.get_content(version.content_uri) do
      {:ok, content} -> {:ok, content}
      {:error, _} -> {:error, :content_unavailable}
    end
  end

  def sequence_detail(conn, %{"id" => id}) do
    story = conn.assigns.current_story

    case Storybox.Stories.SequencePiece
         |> Ash.Query.filter(id == ^id and story_id == ^story.id)
         |> Ash.read_one(authorize?: false) do
      {:ok, nil} ->
        conn |> put_status(404) |> json(%{error: "not found"})

      {:ok, piece} ->
        version_query =
          if piece.approved_version_id do
            Storybox.Stories.SequenceVersion
            |> Ash.Query.filter(id == ^piece.approved_version_id)
            |> Ash.read_one(authorize?: false)
          else
            Storybox.Stories.SequenceVersion
            |> Ash.Query.filter(sequence_piece_id == ^piece.id)
            |> Ash.Query.sort(version_number: :desc)
            |> Ash.Query.limit(1)
            |> Ash.read_one(authorize?: false)
          end

        case version_query do
          {:ok, nil} ->
            conn |> put_status(404) |> json(%{error: "no version available"})

          {:ok, version} ->
            case Storybox.Storage.get_content(version.content_uri) do
              {:ok, content} ->
                characters =
                  Storybox.Stories.Character
                  |> Ash.Query.filter(story_id == ^story.id)
                  |> Ash.read!(authorize?: false)

                world =
                  Storybox.Stories.World
                  |> Ash.Query.filter(story_id == ^story.id)
                  |> Ash.read_one!(authorize?: false)

                json(conn, %{
                  id: piece.id,
                  title: piece.title,
                  act: piece.act,
                  position: piece.position,
                  version: format_version(version),
                  content: content,
                  context: %{
                    world: format_world(world),
                    characters: Enum.map(characters, &format_character/1)
                  }
                })

              {:error, _} ->
                conn |> put_status(503) |> json(%{error: "content unavailable"})
            end

          {:error, _} ->
            conn |> put_status(500) |> json(%{error: "internal error"})
        end

      {:error, _} ->
        conn |> put_status(500) |> json(%{error: "internal error"})
    end
  end

  defp format_version(nil), do: nil

  defp format_version(version) do
    %{
      id: version.id,
      version_number: version.version_number,
      upstream_status: version.upstream_status,
      weights: version.weights,
      inserted_at: version.inserted_at
    }
  end

  defp format_world(nil), do: nil

  defp format_world(world) do
    %{
      id: world.id,
      history: world.history,
      rules: world.rules,
      subtext: world.subtext
    }
  end

  def create_sequence_version(conn, %{"id" => id} = params) do
    story = conn.assigns.current_story
    content = params["content"]

    if is_nil(content) || content == "" do
      conn |> put_status(400) |> json(%{error: "content is required"})
    else
      piece =
        Storybox.Stories.SequencePiece
        |> Ash.Query.filter(id == ^id and story_id == ^story.id)
        |> Ash.read!(authorize?: false)
        |> List.first()

      if piece do
        case Storybox.Stories.SequencePiece
             |> Ash.ActionInput.for_action(:create_version, %{
               content: content,
               sequence_piece_id: piece.id
             })
             |> Ash.run_action(authorize?: false) do
          {:ok, version} ->
            conn |> put_status(201) |> json(format_version(version))

          {:error, _} ->
            conn |> put_status(503) |> json(%{error: "storage error"})
        end
      else
        conn |> put_status(404) |> json(%{error: "not found"})
      end
    end
  end

  def create_scene_version(conn, %{"id" => id} = params) do
    story = conn.assigns.current_story
    content = params["content"]

    if is_nil(content) || content == "" do
      conn |> put_status(400) |> json(%{error: "content is required"})
    else
      scene =
        Storybox.Stories.ScenePiece
        |> Ash.Query.filter(id == ^id)
        |> Ash.read!(authorize?: false)
        |> List.first()

      owner =
        if scene do
          Storybox.Stories.SequencePiece
          |> Ash.Query.filter(id == ^scene.sequence_piece_id and story_id == ^story.id)
          |> Ash.read!(authorize?: false)
          |> List.first()
        end

      if scene && owner do
        case Storybox.Stories.ScenePiece
             |> Ash.ActionInput.for_action(:create_version, %{
               content: content,
               scene_piece_id: scene.id
             })
             |> Ash.run_action(authorize?: false) do
          {:ok, version} ->
            conn |> put_status(201) |> json(format_version(version))

          {:error, _} ->
            conn |> put_status(503) |> json(%{error: "storage error"})
        end
      else
        conn |> put_status(404) |> json(%{error: "not found"})
      end
    end
  end

  defp format_character(char) do
    %{
      id: char.id,
      name: char.name,
      essence: char.essence,
      contradictions: char.contradictions,
      voice: char.voice
    }
  end
end
