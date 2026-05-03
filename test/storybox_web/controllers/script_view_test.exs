defmodule StoryboxWeb.ScriptViewTest do
  use StoryboxWeb.ConnCase

  alias Storybox.Accounts.ApiToken

  # Shared setup creates the following structure (no slot intermediary):
  #
  #   story → sv_1 (Cold open) → sp_v1 (EXT. PARK...), sp_v2 (INT. OFFICE...)
  #         → sv_2 (Inciting incident) → sp_v3 (EXT. STREET...)
  #         → sv_3 (The argument) → sp_v4 (INT. KITCHEN...)
  #         → sv_4 (Aftermath)   (no versions)
  #   snapshot: entries = {sv_1 → sp_v1}  (pins sv_1 to old v1; others not listed)
  #   other_story: for token isolation tests
  #
  #   approved_version_id removed in issue #94; mode=approved returns nil for all scenes

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

    make_sv = fn title ->
      {:ok, scene} =
        Storybox.Stories.Scene
        |> Ash.Changeset.for_create(:create, %{title: title, story_id: story.id})
        |> Ash.create(authorize?: false)

      {:ok, sv} =
        Storybox.Stories.ScriptView
        |> Ash.Changeset.for_create(:create, %{scene_id: scene.id})
        |> Ash.create(authorize?: false)

      {sv, scene}
    end

    {sv_1, scene_1} = make_sv.("Cold open")
    {sv_2, scene_2} = make_sv.("Inciting incident")
    {_sv_3, scene_3} = make_sv.("The argument")
    {sv_4, _scene_4} = make_sv.("Aftermath")

    {:ok, sp_v1} =
      Storybox.Stories.ScriptPiece
      |> Ash.ActionInput.for_action(:create_version, %{
        scene_id: scene_1.id,
        content: "EXT. PARK - DAY\n\nFirst draft."
      })
      |> Ash.run_action(authorize?: false)

    {:ok, sp_v2} =
      Storybox.Stories.ScriptPiece
      |> Ash.ActionInput.for_action(:create_version, %{
        scene_id: scene_1.id,
        content: "INT. OFFICE - NIGHT\n\nRevised."
      })
      |> Ash.run_action(authorize?: false)

    {:ok, _sp_v3} =
      Storybox.Stories.ScriptPiece
      |> Ash.ActionInput.for_action(:create_version, %{
        scene_id: scene_2.id,
        content: "EXT. STREET - DAY\n\nSomething happens."
      })
      |> Ash.run_action(authorize?: false)

    {:ok, _sp_v4} =
      Storybox.Stories.ScriptPiece
      |> Ash.ActionInput.for_action(:create_version, %{
        scene_id: scene_3.id,
        content: "INT. KITCHEN - DAY\n\nThey argue."
      })
      |> Ash.run_action(authorize?: false)

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
      sv_1: sv_1,
      sv_2: sv_2,
      sv_4: sv_4,
      scene_1: scene_1,
      sp_v1: sp_v1,
      sp_v2: sp_v2,
      snapshot: snapshot
    }
  end

  defp authed(conn, raw_token), do: put_req_header(conn, "authorization", "Bearer #{raw_token}")

  defp get_script(conn, story, raw_token, params) do
    query = URI.encode_query(params)
    conn |> authed(raw_token) |> get("/api/stories/#{story.id}/views/script?#{query}")
  end

  defp find_scene(body, title), do: Enum.find(body["scenes"], &(&1["title"] == title))

  # ── mode=latest ─────────────────────────────────────────────────────────────

  describe "GET /api/stories/:story_id/views/script?mode=latest" do
    test "returns all scenes resolved to their highest-numbered version with content", %{
      conn: conn,
      story: story,
      raw_token: raw_token
    } do
      conn = get_script(conn, story, raw_token, %{mode: "latest"})
      body = json_response(conn, 200)

      assert body["story_id"] == story.id
      assert body["mode"] == "latest"
      assert body["snapshot_id"] == nil
      assert length(body["scenes"]) == 4

      cold_open = find_scene(body, "Cold open")
      assert cold_open["version"]["version_number"] == 2
      assert cold_open["content"] == "INT. OFFICE - NIGHT\n\nRevised."

      inciting = find_scene(body, "Inciting incident")
      assert inciting["version"]["version_number"] == 1
      assert inciting["content"] == "EXT. STREET - DAY\n\nSomething happens."
    end

    test "scene with no versions returns null version and null content without crashing", %{
      conn: conn,
      story: story,
      raw_token: raw_token,
      sv_4: sv_4
    } do
      conn = get_script(conn, story, raw_token, %{mode: "latest"})
      aftermath = find_scene(json_response(conn, 200), "Aftermath")

      assert aftermath["id"] == sv_4.id
      assert aftermath["version"] == nil
      assert aftermath["content"] == nil
    end
  end

  # ── mode=approved ────────────────────────────────────────────────────────────
  # approved_version_id was removed in issue #94; approval redesigned via
  # ScriptViewVersion. All scenes return nil version and nil content until
  # the new approval mechanism is implemented.

  describe "GET /api/stories/:story_id/views/script?mode=approved" do
    test "all scenes return nil version and nil content", %{
      conn: conn,
      story: story,
      raw_token: raw_token
    } do
      conn = get_script(conn, story, raw_token, %{mode: "approved"})
      body = json_response(conn, 200)

      assert body["mode"] == "approved"

      Enum.each(body["scenes"], fn scene ->
        assert scene["version"] == nil
        assert scene["content"] == nil
      end)
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

      cold_open = find_scene(body, "Cold open")
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

      inciting = find_scene(body, "Inciting incident")
      assert inciting["version"] == nil
      assert inciting["content"] == nil

      argument = find_scene(body, "The argument")
      assert argument["version"] == nil
      assert argument["content"] == nil

      aftermath = find_scene(body, "Aftermath")
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
      {:ok, _bad_version} =
        Storybox.Stories.ScriptPiece
        |> Ash.Changeset.for_create(:create, %{
          scene_id: scene_1.id,
          content_uri: "storybox://scenes/#{scene_1.id}/script_pieces/v999_nonexistent.fountain",
          version_number: 99,
          weights: %{}
        })
        |> Ash.create(authorize?: false)

      conn = get_script(conn, story, raw_token, %{mode: "latest"})
      assert json_response(conn, 503)["error"] == "content unavailable"
    end

    test "response does not expose content_uri in any version object", %{
      conn: conn,
      story: story,
      raw_token: raw_token
    } do
      conn = get_script(conn, story, raw_token, %{mode: "latest"})
      body = json_response(conn, 200)

      body["scenes"]
      |> Enum.each(fn scene ->
        if scene["version"] do
          refute Map.has_key?(scene["version"], "content_uri")
        end
      end)
    end
  end
end
