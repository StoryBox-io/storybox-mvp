defmodule StoryboxWeb.ScriptViewTest do
  use StoryboxWeb.ConnCase

  alias Storybox.Accounts.ApiToken

  # Shared setup creates the following structure:
  #
  #   story → tv_1 (Act I) → sv_1 → sp_v1 (EXT. PARK...), sp_v2 (INT. OFFICE...) ★ approved
  #                         → sv_2 → sp_v3 (EXT. STREET...)   no approved version
  #         → tv_2 (Act II) → sv_3 → sp_v4 (INT. KITCHEN...) ★ approved
  #                          → sv_4   (no versions)
  #   snapshot: entries = {sv_1 → sp_v1}  (pins sv_1 to old v1; others not listed)
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

    {:ok, tv_1} =
      Storybox.Stories.TreatmentView
      |> Ash.Changeset.for_create(:create, %{
        title: "Opening",
        act: "Act I",
        position: 1,
        story_id: story.id
      })
      |> Ash.create(authorize?: false)

    {:ok, tv_2} =
      Storybox.Stories.TreatmentView
      |> Ash.Changeset.for_create(:create, %{
        title: "Confrontation",
        act: "Act II",
        position: 1,
        story_id: story.id
      })
      |> Ash.create(authorize?: false)

    make_sv = fn tv_id, title, position ->
      {:ok, scene} =
        Storybox.Stories.Scene
        |> Ash.Changeset.for_create(:create, %{title: title, story_id: story.id})
        |> Ash.create(authorize?: false)

      {:ok, _tvs} =
        Storybox.Stories.TreatmentViewScene
        |> Ash.Changeset.for_create(:create, %{
          treatment_view_id: tv_id,
          scene_id: scene.id,
          position: position
        })
        |> Ash.create(authorize?: false)

      {:ok, sv} =
        Storybox.Stories.ScriptView
        |> Ash.Changeset.for_create(:create, %{title: title, scene_id: scene.id})
        |> Ash.create(authorize?: false)

      sv
    end

    sv_1 = make_sv.(tv_1.id, "Cold open", 1)
    sv_2 = make_sv.(tv_1.id, "Inciting incident", 2)
    sv_3 = make_sv.(tv_2.id, "The argument", 1)
    sv_4 = make_sv.(tv_2.id, "Aftermath", 2)

    {:ok, sp_v1} =
      Storybox.Stories.ScriptView
      |> Ash.ActionInput.for_action(:create_version, %{
        script_view_id: sv_1.id,
        content: "EXT. PARK - DAY\n\nFirst draft."
      })
      |> Ash.run_action(authorize?: false)

    {:ok, sp_v2} =
      Storybox.Stories.ScriptView
      |> Ash.ActionInput.for_action(:create_version, %{
        script_view_id: sv_1.id,
        content: "INT. OFFICE - NIGHT\n\nRevised."
      })
      |> Ash.run_action(authorize?: false)

    {:ok, sv_1} =
      sv_1
      |> Ash.Changeset.for_update(:approve_version, %{version_id: sp_v2.id})
      |> Ash.update(authorize?: false)

    {:ok, sp_v3} =
      Storybox.Stories.ScriptView
      |> Ash.ActionInput.for_action(:create_version, %{
        script_view_id: sv_2.id,
        content: "EXT. STREET - DAY\n\nSomething happens."
      })
      |> Ash.run_action(authorize?: false)

    {:ok, sp_v4} =
      Storybox.Stories.ScriptView
      |> Ash.ActionInput.for_action(:create_version, %{
        script_view_id: sv_3.id,
        content: "INT. KITCHEN - DAY\n\nThey argue."
      })
      |> Ash.run_action(authorize?: false)

    {:ok, sv_3} =
      sv_3
      |> Ash.Changeset.for_update(:approve_version, %{version_id: sp_v4.id})
      |> Ash.update(authorize?: false)

    # Snapshot pins sv_1 to sp_v1 (its old version, not the currently approved sp_v2)
    {:ok, snapshot} =
      Storybox.Stories.ScriptSnapshot
      |> Ash.Changeset.for_create(:create, %{
        name: "Test snapshot",
        story_id: story.id,
        entries: %{to_string(sv_1.id) => to_string(sp_v1.id)}
      })
      |> Ash.create(authorize?: false)

    %{
      story: story,
      other_story: other_story,
      raw_token: raw_token,
      tv_1: tv_1,
      tv_2: tv_2,
      sv_1: sv_1,
      sv_2: sv_2,
      sv_3: sv_3,
      sv_4: sv_4,
      sp_v1: sp_v1,
      sp_v2: sp_v2,
      sp_v3: sp_v3,
      sp_v4: sp_v4,
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
      sv_4: sv_4
    } do
      conn = get_script(conn, story, raw_token, %{mode: "latest"})
      confrontation = find_sequence(json_response(conn, 200), "Confrontation")
      aftermath = find_scene(confrontation, "Aftermath")

      assert aftermath["id"] == sv_4.id
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
    test "resolves sv_1 to sp_v1 via the snapshot entries map, not the current approved sp_v2", %{
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

      # sv_2, sv_3, sv_4 are not in the snapshot
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
      sv_1: sv_1
    } do
      {:ok, bad_version} =
        Storybox.Stories.ScriptPiece
        |> Ash.Changeset.for_create(:create, %{
          script_view_id: sv_1.id,
          content_uri:
            "storybox://stories/#{story.id}/scenes/#{sv_1.id}/v999_nonexistent.fountain",
          version_number: 99,
          upstream_status: :current,
          weights: %{}
        })
        |> Ash.create(authorize?: false)

      sv_1
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
