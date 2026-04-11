defmodule StoryboxWeb.ScriptViewTest do
  use StoryboxWeb.ConnCase

  alias Storybox.Accounts.ApiToken

  # Shared setup creates the following structure (see plan for diagram):
  #
  #   story → seq_1 (Act I) → scene_1 → v1 (EXT. PARK...), v2 (INT. OFFICE...) ★ approved
  #                          → scene_2 → v3 (EXT. STREET...)   no approved version
  #         → seq_2 (Act II) → scene_3 → v4 (INT. KITCHEN...) ★ approved
  #                           → scene_4   (no versions)
  #   snapshot: entries = {scene_1 → v1}  (pins scene_1 to old v1; others not listed)
  #   other_story: for token isolation tests

  setup do
    {:ok, user} =
      Storybox.Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "script_view_test@example.com",
        password: "password123!",
        password_confirmation: "password123!"
      })
      |> Ash.create()

    {:ok, story} =
      Storybox.Stories.Story
      |> Ash.Changeset.for_create(:create, %{
        title: "Script Test Story",
        through_lines: ["tension"],
        user_id: user.id
      })
      |> Ash.create()

    {:ok, other_story} =
      Storybox.Stories.Story
      |> Ash.Changeset.for_create(:create, %{title: "Other Story", user_id: user.id})
      |> Ash.create()

    {:ok, raw_token, _} = ApiToken.generate(%{story_id: story.id, user_id: user.id})

    {:ok, seq_1} =
      Storybox.Stories.SequencePiece
      |> Ash.Changeset.for_create(:create, %{
        title: "Opening",
        act: "Act I",
        position: 1,
        story_id: story.id
      })
      |> Ash.create(authorize?: false)

    {:ok, seq_2} =
      Storybox.Stories.SequencePiece
      |> Ash.Changeset.for_create(:create, %{
        title: "Confrontation",
        act: "Act II",
        position: 1,
        story_id: story.id
      })
      |> Ash.create(authorize?: false)

    {:ok, scene_1} =
      Storybox.Stories.ScenePiece
      |> Ash.Changeset.for_create(:create, %{
        title: "Cold open",
        position: 1,
        sequence_piece_id: seq_1.id
      })
      |> Ash.create(authorize?: false)

    {:ok, scene_2} =
      Storybox.Stories.ScenePiece
      |> Ash.Changeset.for_create(:create, %{
        title: "Inciting incident",
        position: 2,
        sequence_piece_id: seq_1.id
      })
      |> Ash.create(authorize?: false)

    {:ok, scene_3} =
      Storybox.Stories.ScenePiece
      |> Ash.Changeset.for_create(:create, %{
        title: "The argument",
        position: 1,
        sequence_piece_id: seq_2.id
      })
      |> Ash.create(authorize?: false)

    {:ok, scene_4} =
      Storybox.Stories.ScenePiece
      |> Ash.Changeset.for_create(:create, %{
        title: "Aftermath",
        position: 2,
        sequence_piece_id: seq_2.id
      })
      |> Ash.create(authorize?: false)

    {:ok, v1} =
      Storybox.Stories.ScenePiece
      |> Ash.ActionInput.for_action(:create_version, %{
        scene_piece_id: scene_1.id,
        content: "EXT. PARK - DAY\n\nFirst draft."
      })
      |> Ash.run_action(authorize?: false)

    {:ok, v2} =
      Storybox.Stories.ScenePiece
      |> Ash.ActionInput.for_action(:create_version, %{
        scene_piece_id: scene_1.id,
        content: "INT. OFFICE - NIGHT\n\nRevised."
      })
      |> Ash.run_action(authorize?: false)

    {:ok, scene_1} =
      scene_1
      |> Ash.Changeset.for_update(:approve_version, %{version_id: v2.id})
      |> Ash.update(authorize?: false)

    {:ok, v3} =
      Storybox.Stories.ScenePiece
      |> Ash.ActionInput.for_action(:create_version, %{
        scene_piece_id: scene_2.id,
        content: "EXT. STREET - DAY\n\nSomething happens."
      })
      |> Ash.run_action(authorize?: false)

    {:ok, v4} =
      Storybox.Stories.ScenePiece
      |> Ash.ActionInput.for_action(:create_version, %{
        scene_piece_id: scene_3.id,
        content: "INT. KITCHEN - DAY\n\nThey argue."
      })
      |> Ash.run_action(authorize?: false)

    {:ok, scene_3} =
      scene_3
      |> Ash.Changeset.for_update(:approve_version, %{version_id: v4.id})
      |> Ash.update(authorize?: false)

    # Snapshot pins scene_1 to v1 (its old version, not the currently approved v2)
    {:ok, snapshot} =
      Storybox.Stories.ScriptSnapshot
      |> Ash.Changeset.for_create(:create, %{
        name: "Test snapshot",
        story_id: story.id,
        entries: %{to_string(scene_1.id) => to_string(v1.id)}
      })
      |> Ash.create(authorize?: false)

    %{
      story: story,
      other_story: other_story,
      raw_token: raw_token,
      seq_1: seq_1,
      seq_2: seq_2,
      scene_1: scene_1,
      scene_2: scene_2,
      scene_3: scene_3,
      scene_4: scene_4,
      v1: v1,
      v2: v2,
      v3: v3,
      v4: v4,
      snapshot: snapshot
    }
  end

  defp authed(conn, raw_token), do: put_req_header(conn, "authorization", "Bearer #{raw_token}")

  defp get_script(conn, story, raw_token, params) do
    query = URI.encode_query(params)
    conn |> authed(raw_token) |> get("/api/stories/#{story.id}/views/script?#{query}")
  end

  defp find_sequence(body, title), do: Enum.find(body["sequences"], &(&1["title"] == title))
  defp find_scene(sequence, title), do: Enum.find(sequence["scenes"], &(&1["title"] == title))

  # ── mode=latest ─────────────────────────────────────────────────────────────

  describe "GET /api/stories/:story_id/views/script?mode=latest" do
    test "returns all sequences with each scene resolved to its highest-numbered version and content",
         %{
           conn: conn,
           story: story,
           raw_token: raw_token
         } do
      conn = get_script(conn, story, raw_token, %{mode: "latest"})
      body = json_response(conn, 200)

      assert body["story_id"] == story.id
      assert body["mode"] == "latest"
      assert body["snapshot_id"] == nil
      assert length(body["sequences"]) == 2

      opening = find_sequence(body, "Opening")
      cold_open = find_scene(opening, "Cold open")
      assert cold_open["version"]["version_number"] == 2
      assert cold_open["content"] == "INT. OFFICE - NIGHT\n\nRevised."

      inciting = find_scene(opening, "Inciting incident")
      assert inciting["version"]["version_number"] == 1
      assert inciting["content"] == "EXT. STREET - DAY\n\nSomething happens."
    end

    test "scenes within a sequence are ordered by position", %{
      conn: conn,
      story: story,
      raw_token: raw_token
    } do
      conn = get_script(conn, story, raw_token, %{mode: "latest"})
      opening = find_sequence(json_response(conn, 200), "Opening")

      positions = Enum.map(opening["scenes"], & &1["position"])
      assert positions == Enum.sort(positions)
      assert hd(opening["scenes"])["title"] == "Cold open"
    end

    test "scene with no versions returns null version and null content without crashing", %{
      conn: conn,
      story: story,
      raw_token: raw_token,
      scene_4: scene_4
    } do
      conn = get_script(conn, story, raw_token, %{mode: "latest"})
      confrontation = find_sequence(json_response(conn, 200), "Confrontation")
      aftermath = find_scene(confrontation, "Aftermath")

      assert aftermath["id"] == scene_4.id
      assert aftermath["version"] == nil
      assert aftermath["content"] == nil
    end
  end

  # ── mode=approved ────────────────────────────────────────────────────────────

  describe "GET /api/stories/:story_id/views/script?mode=approved" do
    test "scenes with an approved version return that version's content", %{
      conn: conn,
      story: story,
      raw_token: raw_token
    } do
      conn = get_script(conn, story, raw_token, %{mode: "approved"})
      body = json_response(conn, 200)

      cold_open = body |> find_sequence("Opening") |> find_scene("Cold open")
      assert cold_open["version"]["version_number"] == 2
      assert cold_open["content"] == "INT. OFFICE - NIGHT\n\nRevised."

      argument = body |> find_sequence("Confrontation") |> find_scene("The argument")
      assert argument["version"]["version_number"] == 1
      assert argument["content"] == "INT. KITCHEN - DAY\n\nThey argue."
    end

    test "scene with no approved version returns null version and null content", %{
      conn: conn,
      story: story,
      raw_token: raw_token
    } do
      conn = get_script(conn, story, raw_token, %{mode: "approved"})
      body = json_response(conn, 200)

      inciting = body |> find_sequence("Opening") |> find_scene("Inciting incident")
      assert inciting["version"] == nil
      assert inciting["content"] == nil

      aftermath = body |> find_sequence("Confrontation") |> find_scene("Aftermath")
      assert aftermath["version"] == nil
      assert aftermath["content"] == nil
    end
  end

  # ── mode=snapshot ────────────────────────────────────────────────────────────

  describe "GET /api/stories/:story_id/views/script?mode=snapshot" do
    test "resolves scene_1 to v1 via the snapshot entries map, not the current approved v2", %{
      conn: conn,
      story: story,
      raw_token: raw_token,
      snapshot: snapshot
    } do
      conn = get_script(conn, story, raw_token, %{mode: "snapshot", snapshot_id: snapshot.id})
      body = json_response(conn, 200)

      assert body["snapshot_id"] == snapshot.id

      cold_open = body |> find_sequence("Opening") |> find_scene("Cold open")
      assert cold_open["version"]["version_number"] == 1
      assert cold_open["content"] == "EXT. PARK - DAY\n\nFirst draft."
    end

    test "scenes not listed in the snapshot entries return null version and null content", %{
      conn: conn,
      story: story,
      raw_token: raw_token,
      snapshot: snapshot
    } do
      conn = get_script(conn, story, raw_token, %{mode: "snapshot", snapshot_id: snapshot.id})
      body = json_response(conn, 200)

      # scene_2, scene_3, scene_4 are not in the snapshot
      inciting = body |> find_sequence("Opening") |> find_scene("Inciting incident")
      assert inciting["version"] == nil
      assert inciting["content"] == nil

      argument = body |> find_sequence("Confrontation") |> find_scene("The argument")
      assert argument["version"] == nil
      assert argument["content"] == nil

      aftermath = body |> find_sequence("Confrontation") |> find_scene("Aftermath")
      assert aftermath["version"] == nil
      assert aftermath["content"] == nil
    end

    test "snapshot belonging to a different story returns 404", %{
      conn: conn,
      story: story,
      other_story: other_story,
      raw_token: raw_token
    } do
      {:ok, other_snapshot} =
        Storybox.Stories.ScriptSnapshot
        |> Ash.Changeset.for_create(:create, %{
          name: "Other",
          story_id: other_story.id,
          entries: %{}
        })
        |> Ash.create(authorize?: false)

      conn =
        get_script(conn, story, raw_token, %{mode: "snapshot", snapshot_id: other_snapshot.id})

      assert json_response(conn, 404)["error"] == "snapshot not found"
    end
  end

  # ── parameter validation ─────────────────────────────────────────────────────

  describe "parameter validation" do
    test "missing mode param returns 400", %{conn: conn, story: story, raw_token: raw_token} do
      conn = conn |> authed(raw_token) |> get("/api/stories/#{story.id}/views/script")
      assert json_response(conn, 400)["error"] == "mode is required"
    end

    test "unrecognised mode value returns 400", %{conn: conn, story: story, raw_token: raw_token} do
      conn = get_script(conn, story, raw_token, %{mode: "draft"})
      assert json_response(conn, 400)["error"] == "mode must be latest, approved, or snapshot"
    end

    test "mode=snapshot without snapshot_id returns 400", %{
      conn: conn,
      story: story,
      raw_token: raw_token
    } do
      conn = get_script(conn, story, raw_token, %{mode: "snapshot"})
      assert json_response(conn, 400)["error"] == "snapshot_id is required when mode is snapshot"
    end
  end

  # ── auth & content guard ─────────────────────────────────────────────────────

  describe "auth and content guards" do
    test "token scoped to a different story returns 403", %{
      conn: conn,
      other_story: other_story,
      raw_token: raw_token
    } do
      conn =
        conn
        |> authed(raw_token)
        |> get("/api/stories/#{other_story.id}/views/script?mode=latest")

      assert json_response(conn, 403)["error"] == "forbidden"
    end

    test "version with a missing MinIO object returns 503", %{
      conn: conn,
      story: story,
      raw_token: raw_token,
      scene_1: scene_1
    } do
      {:ok, bad_version} =
        Storybox.Stories.SceneVersion
        |> Ash.Changeset.for_create(:create, %{
          scene_piece_id: scene_1.id,
          content_uri:
            "storybox://stories/#{story.id}/scenes/#{scene_1.id}/v999_nonexistent.fountain",
          version_number: 99,
          upstream_status: :current,
          weights: %{}
        })
        |> Ash.create(authorize?: false)

      scene_1
      |> Ash.Changeset.for_update(:approve_version, %{version_id: bad_version.id})
      |> Ash.update(authorize?: false)

      conn = get_script(conn, story, raw_token, %{mode: "approved"})
      assert json_response(conn, 503)["error"] == "content unavailable"
    end

    test "response does not expose content_uri in any version object", %{
      conn: conn,
      story: story,
      raw_token: raw_token
    } do
      conn = get_script(conn, story, raw_token, %{mode: "latest"})
      body = json_response(conn, 200)

      body["sequences"]
      |> Enum.flat_map(& &1["scenes"])
      |> Enum.each(fn scene ->
        if scene["version"] do
          refute Map.has_key?(scene["version"], "content_uri")
        end
      end)
    end
  end
end
