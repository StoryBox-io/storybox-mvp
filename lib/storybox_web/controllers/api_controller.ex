defmodule StoryboxWeb.ApiController do
  use StoryboxWeb, :controller

  require Ash.Query

  def token(conn, %{"email" => email, "password" => password, "story_id" => story_id}) do
    strategy = AshAuthentication.Info.strategy!(Storybox.Accounts.User, :password)

    case AshAuthentication.Strategy.action(strategy, :sign_in, %{
           email: email,
           password: password
         }) do
      {:ok, user} ->
        case Storybox.Stories.Story
             |> Ash.Query.filter(id == ^story_id and user_id == ^user.id)
             |> Ash.read_one(authorize?: false) do
          {:ok, nil} ->
            conn |> put_status(404) |> json(%{error: "story not found"})

          {:ok, _story} ->
            case Storybox.Accounts.ApiToken.generate(%{
                   story_id: story_id,
                   user_id: user.id
                 }) do
              {:ok, raw_token, _record} ->
                json(conn, %{token: raw_token})

              {:error, _} ->
                conn |> put_status(500) |> json(%{error: "failed to generate token"})
            end

          {:error, _} ->
            conn |> put_status(500) |> json(%{error: "internal error"})
        end

      {:error, _} ->
        conn |> put_status(401) |> json(%{error: "invalid credentials"})
    end
  end

  def token(conn, _params) do
    conn |> put_status(422) |> json(%{error: "email, password, and story_id are required"})
  end

  def ping(conn, %{"story_id" => story_id}) do
    json(conn, %{status: "ok", story_id: story_id})
  end

  def synopsis_view(conn, _params) do
    story = conn.assigns.current_story

    synopsis_view =
      Storybox.Stories.SynopsisView
      |> Ash.Query.filter(story_id == ^story.id)
      |> Ash.read_one(authorize?: false)

    case synopsis_view do
      {:ok, nil} ->
        conn
        |> put_status(404)
        |> json(%{error: "no synopsis found"})

      {:ok, view} ->
        latest_vv =
          Storybox.Stories.SynopsisViewVersion
          |> Ash.Query.filter(synopsis_view_id == ^view.id)
          |> Ash.Query.sort(version_number: :desc)
          |> Ash.Query.limit(1)
          |> Ash.read_one(authorize?: false)

        case latest_vv do
          {:ok, nil} ->
            conn
            |> put_status(404)
            |> json(%{error: "no synopsis found"})

          {:ok, vv} ->
            json(conn, %{
              story_id: story.id,
              synopsis_view_id: view.id,
              version_number: vv.version_number,
              inserted_at: vv.inserted_at
            })

          {:error, _} ->
            conn
            |> put_status(500)
            |> json(%{error: "internal error"})
        end

      {:error, _} ->
        conn
        |> put_status(500)
        |> json(%{error: "internal error"})
    end
  end

  def script_view(conn, params) do
    story = conn.assigns.current_story

    case parse_script_view_mode(params) do
      {:error, reason} ->
        conn |> put_status(400) |> json(%{error: reason})

      {:ok, mode, snapshot_id} ->
        case assemble_script_view(story, mode, snapshot_id) do
          {:error, :snapshot_not_found} ->
            conn |> put_status(404) |> json(%{error: "snapshot not found"})

          {:error, :content_unavailable} ->
            conn |> put_status(503) |> json(%{error: "content unavailable"})

          {:ok, response} ->
            json(conn, response)
        end
    end
  end

  # `mode` is optional and defaults to "latest". `mode=snapshot` requires a
  # `snapshot_id` addressing a StoryScriptViewVersion.
  defp parse_script_view_mode(params) do
    case Map.get(params, "mode", "latest") do
      mode when mode in ["latest", "approved"] ->
        {:ok, mode, nil}

      "snapshot" ->
        case params do
          %{"snapshot_id" => id} when is_binary(id) and id != "" ->
            {:ok, "snapshot", id}

          _ ->
            {:error, "snapshot_id is required when mode is snapshot"}
        end

      _ ->
        {:error, "mode must be latest, approved, or snapshot"}
    end
  end

  # `mode=approved` is a stub: no approval has been recorded, so there is no
  # StoryScriptViewVersion to traverse (issue #76, orchestrator Q2).
  defp assemble_script_view(_story, "approved", _snapshot_id) do
    {:ok, empty_script_view("approved", nil)}
  end

  defp assemble_script_view(story, mode, snapshot_id) do
    story_script_view =
      Storybox.Stories.StoryScriptView
      |> Ash.Query.filter(story_id == ^story.id)
      |> Ash.read_one!(authorize?: false)

    case resolve_story_script_vv(mode, snapshot_id, story_script_view) do
      {:error, reason} ->
        {:error, reason}

      {:ok, nil} ->
        {:ok, empty_script_view(mode, nil)}

      {:ok, ssvv} ->
        case traverse_and_build(mode, ssvv) do
          {:error, reason} ->
            {:error, reason}

          {:ok, content, unresolvable} ->
            {:ok,
             %{
               format: "fountain",
               resolved: unresolvable == [],
               mode: mode,
               story_script_view_version_id: ssvv.id,
               unresolvable: unresolvable,
               content: content
             }}
        end
    end
  end

  defp empty_script_view(mode, ssvv_id) do
    %{
      format: "fountain",
      resolved: false,
      mode: mode,
      story_script_view_version_id: ssvv_id,
      unresolvable: [],
      content: ""
    }
  end

  # Resolves the StoryScriptViewVersion to traverse: latest for "latest",
  # the exact VV addressed by `snapshot_id` for "snapshot". A snapshot_id that
  # does not belong to this story's StoryScriptView is treated as not found.
  defp resolve_story_script_vv("snapshot", _snapshot_id, nil), do: {:error, :snapshot_not_found}

  defp resolve_story_script_vv(_mode, _snapshot_id, nil), do: {:ok, nil}

  defp resolve_story_script_vv("latest", _snapshot_id, story_script_view) do
    ssvv =
      Storybox.Stories.StoryScriptViewVersion
      |> Ash.Query.filter(story_script_view_id == ^story_script_view.id)
      |> Ash.Query.sort(version_number: :desc)
      |> Ash.Query.limit(1)
      |> Ash.read_one!(authorize?: false)

    {:ok, ssvv}
  end

  defp resolve_story_script_vv("snapshot", snapshot_id, story_script_view) do
    case Storybox.Stories.StoryScriptViewVersion
         |> Ash.Query.filter(id == ^snapshot_id and story_script_view_id == ^story_script_view.id)
         |> Ash.read_one(authorize?: false) do
      {:ok, nil} -> {:error, :snapshot_not_found}
      {:ok, ssvv} -> {:ok, ssvv}
      {:error, _} -> {:error, :snapshot_not_found}
    end
  end

  # Walks the V/VV stack StoryScriptVV → SequenceVV → ScriptVV → ScriptPiece.
  # Returns `{:ok, joined_content, unresolvable}` or `{:error, :content_unavailable}`.
  # Null-pin Segments at any layer are recorded in `unresolvable` and never
  # silently skipped.
  defp traverse_and_build(mode, ssvv) do
    {sequence_vvs, unresolvable} =
      ssvv.id
      |> load_segments(:story_script_vv)
      |> resolve_layer(mode, nil, [], fn seg, _parent ->
        %{layer: "story_script", position: seg.position}
      end)

    {script_vvs, unresolvable} =
      descend(sequence_vvs, :sequence_vv, mode, unresolvable, fn seg, seq_vv ->
        %{layer: "sequence", sequence_view_version_id: seq_vv.id, position: seg.position}
      end)

    {pieces, unresolvable} =
      descend(script_vvs, :script_vv, mode, unresolvable, fn seg, script_vv ->
        %{layer: "script", script_view_version_id: script_vv.id, position: seg.position}
      end)

    case fetch_all_content(pieces) do
      {:error, :content_unavailable} -> {:error, :content_unavailable}
      {:ok, fragments} -> {:ok, Enum.join(fragments, "\n\n"), unresolvable}
    end
  end

  # For each parent ViewVersion, load its Segments and resolve them, threading
  # the accumulated `unresolvable` list through.
  defp descend(parents, view_version_type, mode, unresolvable, unresolvable_entry) do
    Enum.reduce(parents, {[], unresolvable}, fn parent, {resolved, unres} ->
      {children, unres} =
        parent.id
        |> load_segments(view_version_type)
        |> resolve_layer(mode, parent, unres, unresolvable_entry)

      {resolved ++ children, unres}
    end)
  end

  defp resolve_layer(segments, mode, parent, unresolvable, unresolvable_entry) do
    Enum.reduce(segments, {[], unresolvable}, fn seg, {resolved, unres} ->
      case resolve_segment(mode, seg) do
        nil -> {resolved, unres ++ [unresolvable_entry.(seg, parent)]}
        target -> {resolved ++ [target], unres}
      end
    end)
  end

  # Resolves a Segment's Pin to the target to traverse into. `snapshot` follows
  # the discrete pin exactly; `latest` jumps to the lineage head (orchestrator Q1).
  defp resolve_segment(_mode, %{pin_id: nil}), do: nil

  defp resolve_segment("snapshot", %{pin_id: pin_id, pin_type: pin_type}) do
    load_pin(pin_type, pin_id)
  end

  defp resolve_segment("latest", %{pin_id: pin_id, pin_type: pin_type}) do
    pin_type |> load_pin(pin_id) |> lineage_head(pin_type)
  end

  defp load_pin(:sequence_vv, id), do: read_by_id(Storybox.Stories.SequenceViewVersion, id)
  defp load_pin(:script_vv, id), do: read_by_id(Storybox.Stories.ScriptViewVersion, id)
  defp load_pin(:script_piece, id), do: read_by_id(Storybox.Stories.ScriptPiece, id)

  defp lineage_head(nil, _pin_type), do: nil

  defp lineage_head(%{sequence_view_id: sequence_view_id}, :sequence_vv) do
    Storybox.Stories.SequenceViewVersion
    |> Ash.Query.filter(sequence_view_id == ^sequence_view_id)
    |> latest_version()
  end

  defp lineage_head(%{script_view_id: script_view_id}, :script_vv) do
    Storybox.Stories.ScriptViewVersion
    |> Ash.Query.filter(script_view_id == ^script_view_id)
    |> latest_version()
  end

  defp lineage_head(%{scene_id: scene_id}, :script_piece) do
    Storybox.Stories.ScriptPiece
    |> Ash.Query.filter(scene_id == ^scene_id)
    |> latest_version()
  end

  defp latest_version(query) do
    query
    |> Ash.Query.sort(version_number: :desc)
    |> Ash.Query.limit(1)
    |> Ash.read_one!(authorize?: false)
  end

  defp read_by_id(resource, id) do
    resource
    |> Ash.Query.filter(id == ^id)
    |> Ash.read_one!(authorize?: false)
  end

  defp load_segments(view_version_id, view_version_type) do
    Storybox.Stories.Segment
    |> Ash.Query.filter(
      view_version_id == ^view_version_id and view_version_type == ^view_version_type
    )
    |> Ash.Query.sort(:position)
    |> Ash.read!(authorize?: false)
  end

  defp fetch_all_content(pieces) do
    Enum.reduce_while(pieces, {:ok, []}, fn piece, {:ok, acc} ->
      case Storybox.Storage.get_content(piece.content_uri) do
        {:ok, content} -> {:cont, {:ok, acc ++ [content]}}
        {:error, _} -> {:halt, {:error, :content_unavailable}}
      end
    end)
  end

  def create_scene_version(conn, %{"id" => id} = params) do
    story = conn.assigns.current_story
    content = params["content"]

    if is_nil(content) || content == "" do
      conn |> put_status(400) |> json(%{error: "content is required"})
    else
      script_view =
        Storybox.Stories.ScriptView
        |> Ash.Query.filter(id == ^id)
        |> Ash.read!(authorize?: false)
        |> List.first()

      owner =
        if script_view do
          Storybox.Stories.Scene
          |> Ash.Query.filter(id == ^script_view.scene_id and story_id == ^story.id)
          |> Ash.read_one!(authorize?: false)
        end

      if script_view && owner do
        case Storybox.Stories.ScriptPiece
             |> Ash.ActionInput.for_action(:create_version, %{
               content: content,
               scene_id: script_view.scene_id
             })
             |> Ash.run_action(authorize?: false) do
          {:ok, piece} ->
            conn |> put_status(201) |> json(format_version(piece))

          {:error, _} ->
            conn |> put_status(503) |> json(%{error: "storage error"})
        end
      else
        conn |> put_status(404) |> json(%{error: "not found"})
      end
    end
  end

  def list_tasks(conn, params) do
    story = conn.assigns.current_story
    status_str = Map.get(params, "status", "pending")

    case parse_task_status(status_str) do
      {:error, _} ->
        conn
        |> put_status(400)
        |> json(%{error: "status must be pending, in_progress, or complete"})

      {:ok, status} ->
        args = %{status: status, story_id: story.id}

        args =
          case params["component_id"] do
            nil -> args
            id -> Map.put(args, :component_id, id)
          end

        args =
          case parse_int_param(params["limit"]) do
            nil -> args
            n -> Map.put(args, :limit, n)
          end

        args =
          case parse_int_param(params["offset"]) do
            nil -> args
            n -> Map.put(args, :offset, n)
          end

        tasks =
          Storybox.Stories.Task
          |> Ash.Query.for_read(:list_pending, args)
          |> Ash.read!(authorize?: false)

        json(conn, Enum.map(tasks, &format_task/1))
    end
  end

  def mark_task_in_progress(conn, %{"id" => id}) do
    story = conn.assigns.current_story

    case load_task_for_story(id, story.id) do
      nil ->
        conn |> put_status(404) |> json(%{error: "not found"})

      task ->
        case Ash.Changeset.for_update(task, :mark_in_progress, %{})
             |> Ash.update(authorize?: false) do
          {:ok, updated} -> json(conn, format_task(updated))
          {:error, _} -> conn |> put_status(500) |> json(%{error: "internal error"})
        end
    end
  end

  def mark_task_complete(conn, %{"id" => id}) do
    story = conn.assigns.current_story

    case load_task_for_story(id, story.id) do
      nil ->
        conn |> put_status(404) |> json(%{error: "not found"})

      task ->
        case Ash.Changeset.for_update(task, :mark_complete, %{})
             |> Ash.update(authorize?: false) do
          {:ok, updated} -> json(conn, format_task(updated))
          {:error, _} -> conn |> put_status(500) |> json(%{error: "internal error"})
        end
    end
  end

  def cut_synopsis_vv(conn, _params) do
    story = conn.assigns.current_story

    with {:ok, view} <-
           Storybox.Stories.SynopsisView
           |> Ash.ActionInput.for_action(:ensure_for_story, %{story_id: story.id})
           |> Ash.run_action(authorize?: false),
         {:ok, vv} <-
           Storybox.Stories.SynopsisViewVersion
           |> Ash.ActionInput.for_action(:cut, %{synopsis_view_id: view.id})
           |> Ash.run_action(authorize?: false) do
      conn |> put_status(201) |> json(format_cut_vv(vv, :synopsis_vv))
    else
      {:error, _} -> conn |> put_status(500) |> json(%{error: "internal error"})
    end
  end

  def cut_treatment_vv(conn, _params) do
    story = conn.assigns.current_story

    with {:ok, view} <-
           Storybox.Stories.TreatmentView
           |> Ash.ActionInput.for_action(:ensure_for_story, %{story_id: story.id})
           |> Ash.run_action(authorize?: false),
         {:ok, vv} <-
           Storybox.Stories.TreatmentViewVersion
           |> Ash.ActionInput.for_action(:cut, %{treatment_view_id: view.id})
           |> Ash.run_action(authorize?: false) do
      conn |> put_status(201) |> json(format_cut_vv(vv, :treatment_vv))
    else
      {:error, _} -> conn |> put_status(500) |> json(%{error: "internal error"})
    end
  end

  def cut_story_script_vv(conn, _params) do
    story = conn.assigns.current_story

    with {:ok, view} <-
           Storybox.Stories.StoryScriptView
           |> Ash.ActionInput.for_action(:ensure_for_story, %{story_id: story.id})
           |> Ash.run_action(authorize?: false),
         {:ok, vv} <-
           Storybox.Stories.StoryScriptViewVersion
           |> Ash.ActionInput.for_action(:cut, %{story_script_view_id: view.id})
           |> Ash.run_action(authorize?: false) do
      conn |> put_status(201) |> json(format_cut_vv(vv, :story_script_vv))
    else
      {:error, _} -> conn |> put_status(500) |> json(%{error: "internal error"})
    end
  end

  def cut_sequence_vv(conn, %{"seq_id" => seq_id} = params) do
    story = conn.assigns.current_story
    script_view_version_ids = Map.get(params, "script_view_version_ids", [])

    case load_sequence_for_story(seq_id, story.id) do
      nil ->
        conn |> put_status(404) |> json(%{error: "not found"})

      sequence ->
        with {:ok, view} <-
               Storybox.Stories.SequenceView
               |> Ash.ActionInput.for_action(:ensure_for_sequence, %{
                 sequence_id: sequence.id,
                 story_id: story.id
               })
               |> Ash.run_action(authorize?: false),
             {:ok, vv} <-
               Storybox.Stories.SequenceViewVersion
               |> Ash.ActionInput.for_action(:cut, %{
                 sequence_view_id: view.id,
                 script_view_version_ids: script_view_version_ids
               })
               |> Ash.run_action(authorize?: false) do
          conn |> put_status(201) |> json(format_cut_vv(vv, :sequence_vv))
        else
          {:error, _} -> conn |> put_status(500) |> json(%{error: "internal error"})
        end
    end
  end

  def cut_script_vv(conn, %{"scene_id" => scene_id} = params) do
    case params["script_piece_id"] do
      nil ->
        conn |> put_status(400) |> json(%{error: "script_piece_id is required"})

      script_piece_id ->
        scene =
          Storybox.Stories.Scene
          |> Ash.Query.filter(id == ^scene_id)
          |> Ash.read_one!(authorize?: false)

        if is_nil(scene) do
          conn |> put_status(404) |> json(%{error: "not found"})
        else
          piece =
            Storybox.Stories.ScriptPiece
            |> Ash.Query.filter(id == ^script_piece_id and scene_id == ^scene.id)
            |> Ash.read_one!(authorize?: false)

          if is_nil(piece) do
            conn |> put_status(404) |> json(%{error: "not found"})
          else
            with {:ok, view} <-
                   Storybox.Stories.ScriptView
                   |> Ash.ActionInput.for_action(:ensure_for_scene, %{scene_id: scene.id})
                   |> Ash.run_action(authorize?: false),
                 {:ok, vv} <-
                   Storybox.Stories.ScriptViewVersion
                   |> Ash.ActionInput.for_action(:cut, %{
                     script_view_id: view.id,
                     script_piece_id: piece.id
                   })
                   |> Ash.run_action(authorize?: false) do
              conn |> put_status(201) |> json(format_cut_vv(vv, :script_vv))
            else
              {:error, _} -> conn |> put_status(500) |> json(%{error: "internal error"})
            end
          end
        end
    end
  end

  def set_sequence_weights(conn, %{"seq_id" => seq_id} = params) do
    story = conn.assigns.current_story
    weights = params["weights"]

    if is_nil(weights) or not is_map(weights) do
      conn |> put_status(400) |> json(%{error: "weights is required"})
    else
      piece =
        Storybox.Stories.SequencePiece
        |> Ash.Query.filter(story_id == ^story.id and sequence_id == ^seq_id)
        |> Ash.Query.sort(version_number: :desc)
        |> Ash.Query.limit(1)
        |> Ash.read_one(authorize?: false)

      case piece do
        {:ok, nil} ->
          conn |> put_status(404) |> json(%{error: "not found"})

        {:ok, p} ->
          case Ash.Changeset.for_update(p, :set_weights, %{weights: weights})
               |> Ash.update(authorize?: false) do
            {:ok, updated} -> json(conn, format_version(updated))
            {:error, _} -> conn |> put_status(500) |> json(%{error: "internal error"})
          end

        {:error, _} ->
          conn |> put_status(500) |> json(%{error: "internal error"})
      end
    end
  end

  def set_script_piece_weights(conn, %{"scene_id" => scene_id} = params) do
    story = conn.assigns.current_story
    weights = params["weights"]

    if is_nil(weights) or not is_map(weights) do
      conn |> put_status(400) |> json(%{error: "weights is required"})
    else
      scene =
        Storybox.Stories.Scene
        |> Ash.Query.filter(id == ^scene_id and story_id == ^story.id)
        |> Ash.read_one(authorize?: false)

      case scene do
        {:ok, nil} ->
          conn |> put_status(404) |> json(%{error: "not found"})

        {:ok, s} ->
          piece =
            Storybox.Stories.ScriptPiece
            |> Ash.Query.filter(scene_id == ^s.id)
            |> Ash.Query.sort(version_number: :desc)
            |> Ash.Query.limit(1)
            |> Ash.read_one(authorize?: false)

          case piece do
            {:ok, nil} ->
              conn |> put_status(404) |> json(%{error: "not found"})

            {:ok, p} ->
              case Ash.Changeset.for_update(p, :set_weights, %{weights: weights})
                   |> Ash.update(authorize?: false) do
                {:ok, updated} -> json(conn, format_version(updated))
                {:error, _} -> conn |> put_status(500) |> json(%{error: "internal error"})
              end

            {:error, _} ->
              conn |> put_status(500) |> json(%{error: "internal error"})
          end

        {:error, _} ->
          conn |> put_status(500) |> json(%{error: "internal error"})
      end
    end
  end

  def list_characters(conn, _params) do
    story = conn.assigns.current_story

    characters =
      Storybox.Stories.Character
      |> Ash.Query.filter(story_id == ^story.id)
      |> Ash.read!(authorize?: false)

    json(conn, Enum.map(characters, fn c -> %{id: c.id, name: c.name} end))
  end

  def character_detail(conn, %{"char_id" => char_id}) do
    story = conn.assigns.current_story

    case load_character_for_story(char_id, story.id) do
      nil ->
        conn |> put_status(404) |> json(%{error: "not found"})

      character ->
        char_view =
          Storybox.Stories.CharacterView
          |> Ash.Query.filter(character_id == ^character.id)
          |> Ash.read_one!(authorize?: false)

        {latest_vv, segment} =
          if char_view do
            vv =
              Storybox.Stories.CharacterViewVersion
              |> Ash.Query.filter(character_view_id == ^char_view.id)
              |> Ash.Query.sort(version_number: :desc)
              |> Ash.Query.limit(1)
              |> Ash.read_one!(authorize?: false)

            seg =
              if vv do
                char_vv_type = :character_vv

                Storybox.Stories.Segment
                |> Ash.Query.filter(
                  view_version_id == ^vv.id and view_version_type == ^char_vv_type
                )
                |> Ash.read_one!(authorize?: false)
              end

            {vv, seg}
          else
            {nil, nil}
          end

        case resolve_piece_content(segment) do
          {:ok, content} ->
            json(conn, %{
              id: character.id,
              name: character.name,
              character_view_id: char_view && char_view.id,
              version_number: latest_vv && latest_vv.version_number,
              content: content
            })

          {:error, :content_unavailable} ->
            conn |> put_status(503) |> json(%{error: "content unavailable"})
        end
    end
  end

  def create_character_piece(conn, %{"char_id" => char_id} = params) do
    story = conn.assigns.current_story
    content = params["content"]

    if is_nil(content) or content == "" do
      conn |> put_status(400) |> json(%{error: "content is required"})
    else
      case load_character_for_story(char_id, story.id) do
        nil ->
          conn |> put_status(404) |> json(%{error: "not found"})

        character ->
          with {:ok, _piece} <-
                 Storybox.Stories.CharacterPiece
                 |> Ash.ActionInput.for_action(:create_version, %{
                   character_id: character.id,
                   content: content
                 })
                 |> Ash.run_action(authorize?: false),
               {:ok, view} <-
                 Storybox.Stories.CharacterView
                 |> Ash.ActionInput.for_action(:ensure_for_character, %{
                   character_id: character.id
                 })
                 |> Ash.run_action(authorize?: false),
               {:ok, vv} <-
                 Storybox.Stories.CharacterViewVersion
                 |> Ash.ActionInput.for_action(:cut, %{character_view_id: view.id})
                 |> Ash.run_action(authorize?: false) do
            conn |> put_status(201) |> json(format_cut_vv(vv, :character_vv))
          else
            {:error, _} -> conn |> put_status(500) |> json(%{error: "internal error"})
          end
      end
    end
  end

  def world_detail(conn, _params) do
    story = conn.assigns.current_story

    case load_world_for_story(story.id) do
      nil ->
        conn |> put_status(404) |> json(%{error: "not found"})

      world ->
        world_view =
          Storybox.Stories.WorldView
          |> Ash.Query.filter(world_id == ^world.id)
          |> Ash.read_one!(authorize?: false)

        {latest_vv, segment} =
          if world_view do
            vv =
              Storybox.Stories.WorldViewVersion
              |> Ash.Query.filter(world_view_id == ^world_view.id)
              |> Ash.Query.sort(version_number: :desc)
              |> Ash.Query.limit(1)
              |> Ash.read_one!(authorize?: false)

            seg =
              if vv do
                world_vv_type = :world_vv

                Storybox.Stories.Segment
                |> Ash.Query.filter(
                  view_version_id == ^vv.id and view_version_type == ^world_vv_type
                )
                |> Ash.read_one!(authorize?: false)
              end

            {vv, seg}
          else
            {nil, nil}
          end

        case resolve_piece_content(segment) do
          {:ok, content} ->
            json(conn, %{
              world_id: world.id,
              world_view_id: world_view && world_view.id,
              version_number: latest_vv && latest_vv.version_number,
              content: content
            })

          {:error, :content_unavailable} ->
            conn |> put_status(503) |> json(%{error: "content unavailable"})
        end
    end
  end

  def create_world_piece(conn, params) do
    story = conn.assigns.current_story
    content = params["content"]

    if is_nil(content) or content == "" do
      conn |> put_status(400) |> json(%{error: "content is required"})
    else
      case load_world_for_story(story.id) do
        nil ->
          conn |> put_status(404) |> json(%{error: "not found"})

        world ->
          with {:ok, _piece} <-
                 Storybox.Stories.WorldPiece
                 |> Ash.ActionInput.for_action(:create_version, %{
                   world_id: world.id,
                   content: content
                 })
                 |> Ash.run_action(authorize?: false),
               {:ok, view} <-
                 Storybox.Stories.WorldView
                 |> Ash.ActionInput.for_action(:ensure_for_world, %{world_id: world.id})
                 |> Ash.run_action(authorize?: false),
               {:ok, vv} <-
                 Storybox.Stories.WorldViewVersion
                 |> Ash.ActionInput.for_action(:cut, %{world_view_id: view.id})
                 |> Ash.run_action(authorize?: false) do
            conn |> put_status(201) |> json(format_cut_vv(vv, :world_vv))
          else
            {:error, _} -> conn |> put_status(500) |> json(%{error: "internal error"})
          end
      end
    end
  end

  defp load_task_for_story(task_id, story_id) do
    Storybox.Stories.Task
    |> Ash.Query.filter(id == ^task_id and story_id == ^story_id)
    |> Ash.read_one!(authorize?: false)
  end

  defp parse_task_status("pending"), do: {:ok, :pending}
  defp parse_task_status("in_progress"), do: {:ok, :in_progress}
  defp parse_task_status("complete"), do: {:ok, :complete}
  defp parse_task_status(_), do: {:error, :invalid_status}

  defp parse_int_param(nil), do: nil

  defp parse_int_param(s) when is_binary(s) do
    case Integer.parse(s) do
      {n, ""} when n > 0 -> n
      _ -> nil
    end
  end

  defp format_task(task) do
    %{
      id: task.id,
      story_id: task.story_id,
      component_type: task.component_type,
      component_id: task.component_id,
      target_view_id: task.target_view_id,
      target_view_version_id: task.target_view_version_id,
      target_view_type: task.target_view_type,
      type: task.type,
      status: task.status,
      triggered_by_piece_id: task.triggered_by_piece_id,
      triggered_by_piece_type: task.triggered_by_piece_type,
      triggered_by_piece_version: task.triggered_by_piece_version,
      inserted_at: task.inserted_at,
      updated_at: task.updated_at
    }
  end

  defp format_cut_vv(vv, vv_type) do
    unresolvable =
      Storybox.Stories.Segment
      |> Ash.Query.filter(view_version_id == ^vv.id and view_version_type == ^vv_type)
      |> Ash.read!(authorize?: false)
      |> Enum.filter(fn seg -> is_nil(seg.pin_id) end)
      |> Enum.map(fn seg ->
        base = %{id: seg.id, position: seg.position}
        if seg.sequence_id, do: Map.put(base, :sequence_id, seg.sequence_id), else: base
      end)

    %{id: vv.id, version_number: vv.version_number, unresolvable_segments: unresolvable}
  end

  defp load_character_for_story(char_id, story_id) do
    Storybox.Stories.Character
    |> Ash.Query.filter(id == ^char_id and story_id == ^story_id)
    |> Ash.read_one!(authorize?: false)
  end

  defp load_world_for_story(story_id) do
    Storybox.Stories.World
    |> Ash.Query.filter(story_id == ^story_id)
    |> Ash.read_one!(authorize?: false)
  end

  defp resolve_piece_content(nil), do: {:ok, nil}

  defp resolve_piece_content(%{pin_id: nil}), do: {:ok, nil}

  defp resolve_piece_content(%{pin_id: pin_id, pin_type: :character_piece}) do
    piece =
      Storybox.Stories.CharacterPiece
      |> Ash.Query.filter(id == ^pin_id)
      |> Ash.read_one!(authorize?: false)

    case Storybox.Storage.get_content(piece.content_uri) do
      {:ok, content} -> {:ok, content}
      {:error, _} -> {:error, :content_unavailable}
    end
  end

  defp resolve_piece_content(%{pin_id: pin_id, pin_type: :world_piece}) do
    piece =
      Storybox.Stories.WorldPiece
      |> Ash.Query.filter(id == ^pin_id)
      |> Ash.read_one!(authorize?: false)

    case Storybox.Storage.get_content(piece.content_uri) do
      {:ok, content} -> {:ok, content}
      {:error, _} -> {:error, :content_unavailable}
    end
  end

  defp load_sequence_for_story(seq_id, story_id) do
    Storybox.Stories.Sequence
    |> Ash.Query.filter(id == ^seq_id and story_id == ^story_id)
    |> Ash.read_one!(authorize?: false)
  end

  defp format_version(nil), do: nil

  defp format_version(piece) do
    %{
      id: piece.id,
      version_number: piece.version_number,
      weights: piece.weights,
      inserted_at: piece.inserted_at
    }
  end
end
