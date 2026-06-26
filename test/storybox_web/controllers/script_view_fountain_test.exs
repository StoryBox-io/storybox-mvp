defmodule StoryboxWeb.ScriptViewFountainTest do
  use StoryboxWeb.ConnCase

  import StoryboxWeb.ScriptViewHelpers

  alias Storybox.Accounts.ApiToken

  # The shared setup mirrors `ScriptViewTest` — see that module for the full
  # V/VV stack diagram. Fixture builders live in `StoryboxWeb.ScriptViewHelpers`.
  #
  #   story        — full resolvable chain (Scene A DRAFT/REVISED, Scene B ONLY)
  #   unres_story  — StoryScriptVV → SequenceVV with one null-pin Segment
  #   empty_story  — no StoryScriptView at all

  setup do
    {:ok, user} =
      Storybox.Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "script_view_fountain_test@example.com",
        password: "password123!",
        password_confirmation: "password123!"
      })
      |> Ash.create()

    story = create_story(user, "Fountain Test Story")
    unres_story = create_story(user, "Unresolvable Fountain Story")

    {:ok, raw_token, _} = ApiToken.generate(%{story_id: story.id, user_id: user.id})
    {:ok, unres_token, _} = ApiToken.generate(%{story_id: unres_story.id, user_id: user.id})

    # ── main story: full resolvable chain ────────────────────────────────────
    scene_a = create_scene(story, "Scene A", "EXT. SCENE A - NIGHT")
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
      raw_token: raw_token,
      unres_token: unres_token,
      ssvv_v1: ssvv_v1,
      ssvv_v2: ssvv_v2
    }
  end

  defp authed(conn, raw_token), do: put_req_header(conn, "authorization", "Bearer #{raw_token}")

  defp get_script(conn, story, raw_token, params) do
    query = URI.encode_query(params)
    conn |> authed(raw_token) |> get("/api/stories/#{story.id}/views/script?#{query}")
  end

  # ── mode=latest ──────────────────────────────────────────────────────────

  describe "GET /views/script?format=fountain — mode=latest" do
    test "streams the latest content as a chunked text/plain document", %{
      conn: conn,
      story: story,
      raw_token: raw_token
    } do
      conn = get_script(conn, story, raw_token, %{format: "fountain", mode: "latest"})
      body = response(conn, 200)

      assert get_resp_header(conn, "content-type") == ["text/plain; charset=utf-8"]

      # Scene A carries a real slugline (emitted verbatim); Scene B has none, so
      # its `slug` is force-dotted into a Fountain scene heading.
      assert body ==
               "EXT. SCENE A - NIGHT\n\nSCENE A — REVISED\n\n.scene-b\n\nSCENE B — ONLY\n\n"
    end

    test "a fully resolved story has no trailing summary block", %{
      conn: conn,
      story: story,
      raw_token: raw_token
    } do
      body =
        conn
        |> get_script(story, raw_token, %{format: "fountain", mode: "latest"})
        |> response(200)

      refute body =~ "UNRESOLVED SCENES"
      refute body =~ "/* unresolved:"
    end
  end

  # ── mode=snapshot ────────────────────────────────────────────────────────

  describe "GET /views/script?format=fountain — mode=snapshot" do
    test "follows the discrete pins of the addressed StoryScriptViewVersion", %{
      conn: conn,
      story: story,
      raw_token: raw_token,
      ssvv_v1: ssvv_v1
    } do
      conn =
        get_script(conn, story, raw_token, %{
          format: "fountain",
          mode: "snapshot",
          snapshot_id: ssvv_v1.id
        })

      # v1 pins the older chain, so snapshot mode yields DRAFT, not REVISED.
      assert response(conn, 200) ==
               "EXT. SCENE A - NIGHT\n\nSCENE A — DRAFT\n\n.scene-b\n\nSCENE B — ONLY\n\n"
    end

    test "unknown snapshot_id returns 404 JSON before chunking starts", %{
      conn: conn,
      story: story,
      raw_token: raw_token
    } do
      conn =
        get_script(conn, story, raw_token, %{
          format: "fountain",
          mode: "snapshot",
          snapshot_id: Ash.UUID.generate()
        })

      assert json_response(conn, 404)["error"] == "snapshot not found"
    end
  end

  # ── mode=approved ────────────────────────────────────────────────────────

  describe "GET /views/script?format=fountain — mode=approved" do
    test "returns a 200 chunked response with an empty body", %{
      conn: conn,
      story: story,
      raw_token: raw_token
    } do
      conn = get_script(conn, story, raw_token, %{format: "fountain", mode: "approved"})

      assert response(conn, 200) == ""
      assert get_resp_header(conn, "content-type") == ["text/plain; charset=utf-8"]
    end
  end

  # ── unresolvable scenes ──────────────────────────────────────────────────

  describe "unresolvable scenes" do
    test "a null-pin Segment emits an inline comment and a trailing summary", %{
      conn: conn,
      unres_story: unres_story,
      unres_token: unres_token
    } do
      conn = get_script(conn, unres_story, unres_token, %{format: "fountain", mode: "latest"})
      body = response(conn, 200)

      # The null pin sits at the sequence layer, so it is labelled positionally.
      assert body =~ "/* unresolved: scene-position-1 */"
      assert body =~ "/* UNRESOLVED SCENES:\n  - scene-position-1\n*/"
    end

    test "the trailing summary block is a single non-nested block comment", %{
      conn: conn,
      unres_story: unres_story,
      unres_token: unres_token
    } do
      body =
        conn
        |> get_script(unres_story, unres_token, %{format: "fountain", mode: "latest"})
        |> response(200)

      # Fountain block comments do not nest — a parser closes at the first
      # `*/`. The summary must wrap plain-text labels, never re-wrap the
      # `/* */`-formatted inline markers.
      [_, summary] = String.split(body, "/* UNRESOLVED SCENES:", parts: 2)
      refute summary =~ "/*"
    end
  end

  # ── parameter validation ─────────────────────────────────────────────────

  describe "parameter validation" do
    test "an unrecognised format value returns 400 JSON", %{
      conn: conn,
      story: story,
      raw_token: raw_token
    } do
      conn = get_script(conn, story, raw_token, %{format: "xml"})
      assert json_response(conn, 400)["error"] == "format must be json or fountain"
    end

    test "an unrecognised mode value returns 400 JSON", %{
      conn: conn,
      story: story,
      raw_token: raw_token
    } do
      conn = get_script(conn, story, raw_token, %{format: "fountain", mode: "draft"})
      assert json_response(conn, 400)["error"] == "mode must be latest, approved, or snapshot"
    end

    test "mode=snapshot without snapshot_id returns 400 JSON", %{
      conn: conn,
      story: story,
      raw_token: raw_token
    } do
      conn = get_script(conn, story, raw_token, %{format: "fountain", mode: "snapshot"})
      assert json_response(conn, 400)["error"] == "snapshot_id is required when mode is snapshot"
    end
  end

  # ── seeded Little Witch story ────────────────────────────────────────────

  describe "seeded Little Witch story" do
    test "streams the full screenplay with the reckoning gap as a comment", %{
      conn: conn,
      user: user
    } do
      lw_story = create_story(user, "Little Witch")
      :ok = Storybox.Seeds.LittleWitchLoader.seed!(lw_story)
      {:ok, lw_token, _} = ApiToken.generate(%{story_id: lw_story.id, user_id: user.id})

      conn = get_script(conn, lw_story, lw_token, %{format: "fountain", mode: "latest"})
      body = response(conn, 200)

      assert get_resp_header(conn, "content-type") == ["text/plain; charset=utf-8"]
      assert body != ""

      # The scene heading is sourced from the Scene's slugline and emitted before
      # the body; the title-page block the seed file embeds is stripped on load.
      assert body =~ "EXT. CORONATION SQUARE - NIGHT"
      refute body =~ "Source: V5"

      # The "reckoning" sequence has one null-pin Segment in the seed data, so
      # the gap appears inline and in the trailing summary.
      assert body =~ "/* unresolved:"
      assert body =~ "/* UNRESOLVED SCENES:"
    end
  end
end
