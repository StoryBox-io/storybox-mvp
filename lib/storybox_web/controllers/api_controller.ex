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

    latest =
      Storybox.Stories.SynopsisView
      |> Ash.Query.filter(story_id == ^story.id)
      |> Ash.Query.sort(version_number: :desc)
      |> Ash.Query.limit(1)
      |> Ash.read_one(authorize?: false)

    case latest do
      {:ok, nil} ->
        conn
        |> put_status(404)
        |> json(%{error: "no synopsis found"})

      {:ok, view} ->
        case Storybox.Storage.get_content(view.content_uri) do
          {:ok, content} ->
            json(conn, %{
              story_id: story.id,
              version_number: view.version_number,
              inserted_at: view.inserted_at,
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

  def script_view(conn, params) do
    story = conn.assigns.current_story

    case parse_script_mode(params) do
      {:error, reason} ->
        conn |> put_status(400) |> json(%{error: reason})

      {:ok, mode, snapshot_id} ->
        scene_ids =
          Storybox.Stories.Scene
          |> Ash.Query.filter(story_id == ^story.id)
          |> Ash.read!(authorize?: false)
          |> Enum.map(& &1.id)

        script_views =
          case scene_ids do
            [] ->
              []

            ids ->
              Storybox.Stories.ScriptView
              |> Ash.Query.filter(scene_id in ^ids)
              |> Ash.read!(authorize?: false)
          end

        script_view_ids = Enum.map(script_views, & &1.id)

        case resolve_script_versions(mode, snapshot_id, story.id, script_views, script_view_ids) do
          {:error, :snapshot_not_found} ->
            conn |> put_status(404) |> json(%{error: "snapshot not found"})

          {:ok, versions_map} ->
            case build_script_scenes(script_views, versions_map) do
              {:error, :content_unavailable} ->
                conn |> put_status(503) |> json(%{error: "content unavailable"})

              {:ok, scenes_with_content} ->
                scenes =
                  script_views
                  |> Enum.map(fn sv -> scenes_with_content[sv.id] end)
                  |> Enum.reject(&is_nil/1)

                json(conn, %{
                  story_id: story.id,
                  mode: mode,
                  snapshot_id: snapshot_id,
                  scenes: scenes
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

  defp resolve_script_versions("latest", _snapshot_id, _story_id, _script_views, script_view_ids) do
    all_pieces =
      Storybox.Stories.ScriptPiece
      |> Ash.Query.filter(script_view_id in ^script_view_ids)
      |> Ash.read!(authorize?: false)

    versions_map =
      all_pieces
      |> Enum.group_by(& &1.script_view_id)
      |> Map.new(fn {id, ps} -> {id, Enum.max_by(ps, & &1.version_number)} end)

    {:ok, versions_map}
  end

  defp resolve_script_versions(
         "approved",
         _snapshot_id,
         _story_id,
         script_views,
         _script_view_ids
       ) do
    approved_ids =
      script_views
      |> Enum.map(& &1.approved_version_id)
      |> Enum.reject(&is_nil/1)

    pieces_by_id =
      case approved_ids do
        [] ->
          %{}

        ids ->
          Storybox.Stories.ScriptPiece
          |> Ash.Query.filter(id in ^ids)
          |> Ash.read!(authorize?: false)
          |> Map.new(&{&1.id, &1})
      end

    versions_map =
      Map.new(script_views, fn view ->
        {view.id, pieces_by_id[view.approved_version_id]}
      end)

    {:ok, versions_map}
  end

  defp resolve_script_versions("snapshot", snapshot_id, story_id, script_views, _script_view_ids) do
    result =
      Storybox.Stories.ScriptSnapshot
      |> Ash.Query.filter(id == ^snapshot_id and story_id == ^story_id)
      |> Ash.read_one(authorize?: false)

    case result do
      {:ok, nil} ->
        {:error, :snapshot_not_found}

      {:ok, snapshot} ->
        piece_ids = Map.values(snapshot.entries)

        pieces_by_id =
          case piece_ids do
            [] ->
              %{}

            ids ->
              Storybox.Stories.ScriptPiece
              |> Ash.Query.filter(id in ^ids)
              |> Ash.read!(authorize?: false)
              |> Map.new(&{to_string(&1.id), &1})
          end

        versions_map =
          Map.new(script_views, fn view ->
            piece_id = snapshot.entries[to_string(view.id)]
            {view.id, pieces_by_id[piece_id]}
          end)

        {:ok, versions_map}

      {:error, _} ->
        {:error, :snapshot_not_found}
    end
  end

  defp build_script_scenes(script_views, versions_map) do
    Enum.reduce_while(script_views, {:ok, %{}}, fn view, {:ok, acc} ->
      piece = versions_map[view.id]

      case fetch_scene_content(piece) do
        {:error, :content_unavailable} ->
          {:halt, {:error, :content_unavailable}}

        {:ok, content} ->
          scene = %{
            id: view.id,
            title: view.title,
            version: format_version(piece),
            content: content
          }

          {:cont, {:ok, Map.put(acc, view.id, scene)}}
      end
    end)
  end

  defp fetch_scene_content(nil), do: {:ok, nil}

  defp fetch_scene_content(piece) do
    case Storybox.Storage.get_content(piece.content_uri) do
      {:ok, content} -> {:ok, content}
      {:error, _} -> {:error, :content_unavailable}
    end
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
        case Storybox.Stories.ScriptView
             |> Ash.ActionInput.for_action(:create_version, %{
               content: content,
               script_view_id: script_view.id
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

  def upstream_changes(conn, _params) do
    story = conn.assigns.current_story

    scene_ids =
      Storybox.Stories.Scene
      |> Ash.Query.filter(story_id == ^story.id)
      |> Ash.read!(authorize?: false)
      |> Enum.map(& &1.id)

    script_piece_ids =
      case scene_ids do
        [] ->
          []

        ids ->
          Storybox.Stories.ScriptView
          |> Ash.Query.filter(scene_id in ^ids)
          |> Ash.read!(authorize?: false)
          |> Enum.map(& &1.id)
          |> then(fn sv_ids ->
            case sv_ids do
              [] ->
                []

              sv_ids ->
                Storybox.Stories.ScriptPiece
                |> Ash.Query.filter(script_view_id in ^sv_ids)
                |> Ash.read!(authorize?: false)
                |> Enum.map(& &1.id)
            end
          end)
      end

    changes =
      case script_piece_ids do
        [] ->
          []

        ids ->
          Storybox.Stories.UpstreamChange
          |> Ash.Query.filter(piece_version_id in ^ids and acknowledged == false)
          |> Ash.Query.sort(inserted_at: :desc)
          |> Ash.read!(authorize?: false)
      end

    json(conn, %{changes: Enum.map(changes, &format_upstream_change/1)})
  end

  defp format_upstream_change(change) do
    %{
      id: change.id,
      piece_version_type: change.piece_version_type,
      piece_version_id: change.piece_version_id,
      component_type: change.component_type,
      component_id: change.component_id,
      version_before: change.version_before,
      version_after: change.version_after,
      inserted_at: change.inserted_at
    }
  end

  defp format_version(nil), do: nil

  defp format_version(piece) do
    %{
      id: piece.id,
      version_number: piece.version_number,
      upstream_status: piece.upstream_status,
      weights: piece.weights,
      inserted_at: piece.inserted_at
    }
  end
end
