defmodule StoryboxWeb.ScriptViewTest do
  use StoryboxWeb.ConnCase

  import StoryboxWeb.ScriptViewHelpers

  alias Storybox.Accounts.ApiToken
  alias Storybox.Stories.ScriptPiece

  # The shared setup builds the full V/VV stack the script-view endpoint
  # traverses:
  #
  #   story (full chain)
  #     StoryScriptView ssv
  #       ssvv_v1 → pins seq_vv_1   (older snapshot)
  #       ssvv_v2 → pins seq_vv_2   (latest)
  #     SequenceView seq_view
  #       seq_vv_1 → pins scvv_a1, scvv_b1
  #       seq_vv_2 → pins scvv_a2, scvv_b1
  #     Scene A: ScriptPieces a_p1 "DRAFT", a_p2 "REVISED"
  #             ScriptViewVersions scvv_a1 (pins a_p1), scvv_a2 (pins a_p2)
  #     Scene B: ScriptPiece b_p1 "ONLY"; ScriptViewVersion scvv_b1 (pins b_p1)
  #
  #   unres_story — StoryScriptVV → SequenceVV with one null-pin Segment
  #   empty_story — no StoryScriptView at all
  #   other_story — exists only for the cross-story 403 test

  setup do
    {:ok, user} =
      Storybox.Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "script_view_test@example.com",
        password: "password123!",
        password_confirmation: "password123!"
      })
      |> Ash.create()

    story = create_story(user, "Script Test Story")
    unres_story = create_story(user, "Unresolvable Story")
    empty_story = create_story(user, "Empty Story")
    other_story = create_story(user, "Other Story")

    {:ok, raw_token, _} = ApiToken.generate(%{story_id: story.id, user_id: user.id})
    {:ok, unres_token, _} = ApiToken.generate(%{story_id: unres_story.id, user_id: user.id})
    {:ok, empty_token, _} = ApiToken.generate(%{story_id: empty_story.id, user_id: user.id})

    # ── main story: full resolvable chain ────────────────────────────────────
    scene_a = create_scene(story, "Scene A")
    scv_a = create_script_view(scene_a)
    a_p1 = create_script_piece(scene_a, "SCENE A — DRAFT")
    a_p2 = create_script_piece(scene_a, "SCENE A — REVISED")
    scvv_a1 = create_script_vv(scv_a, 1, a_p1)
    scvv_a2 = create_script_vv(scv_a, 2, a_p2)

    scene_b = create_scene(story, "Scene B")
    scv_b = create_script_view(scene_b)
    b_p1 = create_script_piece(scene_b, "SCENE B — ONLY")
    scvv_b1 = create_script_vv(scv_b, 1, b_p1)

    seq = create_sequence(story, "Main Sequence", "sequence-main")
    seq_view = create_sequence_view(story, seq)

    seq_vv_1 =
      create_sequence_vv(seq_view, 1, [pin(:script_vv, scvv_a1), pin(:script_vv, scvv_b1)])

    seq_vv_2 =
      create_sequence_vv(seq_view, 2, [pin(:script_vv, scvv_a2), pin(:script_vv, scvv_b1)])

    ssv = create_story_script_view(story)
    ssvv_v1 = create_story_script_vv(ssv, 1, [pin(:sequence_vv, seq_vv_1)])
    ssvv_v2 = create_story_script_vv(ssv, 2, [pin(:sequence_vv, seq_vv_2)])

    # ── unresolvable story: SequenceVV carries a null-pin Segment ────────────
    u_seq = create_sequence(unres_story, "U Sequence", "u-sequence")
    u_seq_view = create_sequence_view(unres_story, u_seq)
    u_seq_vv = create_sequence_vv(u_seq_view, 1, [nil])
    u_ssv = create_story_script_view(unres_story)
    create_story_script_vv(u_ssv, 1, [pin(:sequence_vv, u_seq_vv)])

    %{
      user: user,
      story: story,
      unres_story: unres_story,
      empty_story: empty_story,
      other_story: other_story,
      raw_token: raw_token,
      unres_token: unres_token,
      empty_token: empty_token,
      scene_a: scene_a,
      ssvv_v1: ssvv_v1,
      ssvv_v2: ssvv_v2,
      u_seq_vv: u_seq_vv
    }
  end

  # ── request helpers ──────────────────────────────────────────────────────

  defp authed(conn, raw_token), do: put_req_header(conn, "authorization", "Bearer #{raw_token}")

  defp get_script(conn, story, raw_token, params) do
    query = URI.encode_query(params)
    conn |> authed(raw_token) |> get("/api/stories/#{story.id}/views/script?#{query}")
  end

  # ── mode=latest ──────────────────────────────────────────────────────────

  describe "GET /api/stories/:story_id/views/script — mode=latest" do
    test "assembles the latest content in sequence order", %{
      conn: conn,
      story: story,
      raw_token: raw_token,
      ssvv_v2: ssvv_v2
    } do
      conn = get_script(conn, story, raw_token, %{mode: "latest"})
      body = json_response(conn, 200)

      assert body["format"] == "fountain"
      assert body["mode"] == "latest"
      assert body["resolved"] == true
      assert body["unresolvable"] == []
      assert body["story_script_view_version_id"] == ssvv_v2.id
      assert body["content"] == "SCENE A — REVISED\n\nSCENE B — ONLY"
    end

    test "missing mode param behaves as mode=latest", %{
      conn: conn,
      story: story,
      raw_token: raw_token
    } do
      explicit = get_script(conn, story, raw_token, %{mode: "latest"}) |> json_response(200)

      default =
        conn
        |> authed(raw_token)
        |> get("/api/stories/#{story.id}/views/script")
        |> json_response(200)

      assert default == explicit
    end

    test "unresolvable SequenceVV Segment yields resolved: false with a sequence-layer entry", %{
      conn: conn,
      unres_story: unres_story,
      unres_token: unres_token,
      u_seq_vv: u_seq_vv
    } do
      conn = get_script(conn, unres_story, unres_token, %{mode: "latest"})
      body = json_response(conn, 200)

      assert body["resolved"] == false
      assert body["content"] == ""

      assert [
               %{
                 "layer" => "sequence",
                 "sequence_view_version_id" => seq_vv_id,
                 "position" => 1
               }
             ] = body["unresolvable"]

      assert seq_vv_id == u_seq_vv.id
    end

    test "story with no StoryScriptViewVersion returns resolved: false and empty content", %{
      conn: conn,
      empty_story: empty_story,
      empty_token: empty_token
    } do
      conn = get_script(conn, empty_story, empty_token, %{mode: "latest"})
      body = json_response(conn, 200)

      assert body["resolved"] == false
      assert body["story_script_view_version_id"] == nil
      assert body["content"] == ""
      assert body["unresolvable"] == []
    end
  end

  # ── mode=snapshot ────────────────────────────────────────────────────────

  describe "GET /api/stories/:story_id/views/script — mode=snapshot" do
    test "follows the discrete pins of the addressed StoryScriptViewVersion", %{
      conn: conn,
      story: story,
      raw_token: raw_token,
      ssvv_v1: ssvv_v1
    } do
      conn = get_script(conn, story, raw_token, %{mode: "snapshot", snapshot_id: ssvv_v1.id})
      body = json_response(conn, 200)

      assert body["mode"] == "snapshot"
      assert body["resolved"] == true
      assert body["story_script_view_version_id"] == ssvv_v1.id
      # v1 pins the older chain, so snapshot mode yields DRAFT, not REVISED
      assert body["content"] == "SCENE A — DRAFT\n\nSCENE B — ONLY"
    end

    test "unknown snapshot_id returns 404", %{conn: conn, story: story, raw_token: raw_token} do
      conn =
        get_script(conn, story, raw_token, %{
          mode: "snapshot",
          snapshot_id: Ash.UUID.generate()
        })

      assert json_response(conn, 404)["error"] == "snapshot not found"
    end

    test "snapshot_id belonging to a different story returns 404", %{
      conn: conn,
      unres_story: unres_story,
      unres_token: unres_token,
      ssvv_v1: ssvv_v1
    } do
      conn =
        get_script(conn, unres_story, unres_token, %{
          mode: "snapshot",
          snapshot_id: ssvv_v1.id
        })

      assert json_response(conn, 404)["error"] == "snapshot not found"
    end
  end

  # ── mode=approved ────────────────────────────────────────────────────────

  describe "GET /api/stories/:story_id/views/script — mode=approved" do
    test "returns resolved: false with empty content (no approval recorded)", %{
      conn: conn,
      story: story,
      raw_token: raw_token
    } do
      conn = get_script(conn, story, raw_token, %{mode: "approved"})
      body = json_response(conn, 200)

      assert body["mode"] == "approved"
      assert body["resolved"] == false
      assert body["story_script_view_version_id"] == nil
      assert body["content"] == ""
      assert body["unresolvable"] == []
    end
  end

  # ── parameter validation ─────────────────────────────────────────────────

  describe "parameter validation" do
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

  # ── auth & content guards ────────────────────────────────────────────────

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

    test "a missing MinIO object returns 503", %{
      conn: conn,
      story: story,
      raw_token: raw_token,
      scene_a: scene_a
    } do
      # A newer ScriptPiece becomes the lineage head for Scene A, but its
      # content object does not exist in storage.
      {:ok, _bad_piece} =
        ScriptPiece
        |> Ash.Changeset.for_create(:create, %{
          scene_id: scene_a.id,
          content_uri: "storybox://scenes/#{scene_a.id}/script_pieces/v999_missing.fountain",
          version_number: 999,
          weights: %{}
        })
        |> Ash.create(authorize?: false)

      conn = get_script(conn, story, raw_token, %{mode: "latest"})
      assert json_response(conn, 503)["error"] == "content unavailable"
    end
  end

  # ── ConnCase: seeded Little Witch story ──────────────────────────────────

  describe "seeded Little Witch story" do
    test "assembles the full screenplay via the V/VV stack", %{conn: conn, user: user} do
      lw_story = create_story(user, "Little Witch")
      :ok = Storybox.Seeds.LittleWitchLoader.seed!(lw_story)
      {:ok, lw_token, _} = ApiToken.generate(%{story_id: lw_story.id, user_id: user.id})

      conn = get_script(conn, lw_story, lw_token, %{mode: "latest"})
      body = json_response(conn, 200)

      assert body["format"] == "fountain"
      assert body["mode"] == "latest"
      assert body["story_script_view_version_id"]
      assert is_binary(body["content"]) and body["content"] != ""

      # The "reckoning" sequence has one null-pin Segment in the seed data,
      # so the assembly is not fully resolved and the gap is reported.
      assert body["resolved"] == false
      assert [%{"layer" => "sequence"}] = body["unresolvable"]
    end
  end
end
