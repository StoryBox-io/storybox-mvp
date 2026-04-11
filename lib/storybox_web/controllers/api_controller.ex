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
