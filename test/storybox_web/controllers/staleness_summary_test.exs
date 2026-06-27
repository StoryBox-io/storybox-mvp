defmodule StoryboxWeb.StalenessSummaryTest do
  use StoryboxWeb.ConnCase

  import StoryboxWeb.ScriptViewHelpers

  alias Storybox.Accounts.ApiToken

  require Ash.Query

  # Cuts a fresh ScriptPiece version for a scene so the scene's lineage head
  # advances past whatever a ScriptViewVersion pinned — turning a script_vv that
  # pins the older piece stale.
  defp bump_script_piece(scene, content) do
    create_script_piece(scene, content)
  end

  # Cuts a fresh ScriptViewVersion for a script_view so the script_view's lineage
  # head advances past whatever a SequenceViewVersion pinned — turning a
  # sequence_vv that pins the older script_vv stale.
  defp bump_script_vv(script_view, version_number, piece) do
    create_script_vv(script_view, version_number, piece)
  end

  setup do
    {:ok, user} =
      Storybox.Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "staleness_summary_test@example.com",
        password: "password123!",
        password_confirmation: "password123!"
      })
      |> Ash.create()

    %{user: user}
  end

  defp authed(conn, raw_token), do: put_req_header(conn, "authorization", "Bearer #{raw_token}")

  defp get_staleness(conn, story, raw_token, params \\ %{}) do
    query = if params == %{}, do: "", else: "?" <> URI.encode_query(params)
    conn |> authed(raw_token) |> get("/api/stories/#{story.id}/staleness#{query}")
  end

  describe "GET /staleness — full summary" do
    test "returns the stale view versions from story_stale_summary", %{
      conn: conn,
      user: user
    } do
      story = create_story(user, "Stale Story")
      {:ok, raw_token, _} = ApiToken.generate(%{story_id: story.id, user_id: user.id})

      # A script_vv pinned at piece v1; a newer piece v2 makes it stale.
      scene = create_scene(story, "Scene One", "INT. ROOM - DAY")
      scv = create_script_view(scene)
      p1 = create_script_piece(scene, "BODY V1")
      scvv = create_script_vv(scv, 1, p1)
      bump_script_piece(scene, "BODY V2")

      body = conn |> get_staleness(story, raw_token) |> json_response(200)

      assert body["story_id"] == story.id
      assert body["sequence_id"] == nil

      assert body["view_versions"] == [%{"id" => scvv.id, "type" => "script_vv"}]
    end

    test "a story with no stale view versions returns an empty list", %{
      conn: conn,
      user: user
    } do
      story = create_story(user, "Fresh Story")
      {:ok, raw_token, _} = ApiToken.generate(%{story_id: story.id, user_id: user.id})

      # A script_vv pinned at the latest piece — not stale.
      scene = create_scene(story, "Scene One", "INT. ROOM - DAY")
      scv = create_script_view(scene)
      p1 = create_script_piece(scene, "BODY V1")
      create_script_vv(scv, 1, p1)

      body = conn |> get_staleness(story, raw_token) |> json_response(200)

      assert body["story_id"] == story.id
      assert body["sequence_id"] == nil
      assert body["view_versions"] == []
    end
  end

  describe "GET /staleness?sequence_id — region scope" do
    setup %{user: user} do
      story = create_story(user, "Region Staleness Story")
      other_story = create_story(user, "Other Story")
      {:ok, raw_token, _} = ApiToken.generate(%{story_id: story.id, user_id: user.id})

      # ── region 1: a stale sequence_vv ────────────────────────────────────────
      scene_1 = create_scene(story, "Scene One", "INT. SEQ ONE - DAY")
      scv_1 = create_script_view(scene_1)
      p_1 = create_script_piece(scene_1, "SEQ ONE BODY")
      scvv_1 = create_script_vv(scv_1, 1, p_1)

      seq_1 = create_sequence(story, "Sequence One", "sequence-one")
      seq_view_1 = create_sequence_view(story, seq_1)
      seq_vv_1 = create_sequence_vv(seq_view_1, 1, [pin(:script_vv, scvv_1)])
      # Newer script_vv → seq_vv_1 pins an older script_vv → stale.
      bump_script_vv(scv_1, 2, create_script_piece(scene_1, "SEQ ONE BODY V2"))

      # ── region 2: a stale sequence_vv ────────────────────────────────────────
      scene_2 = create_scene(story, "Scene Two", "INT. SEQ TWO - DAY")
      scv_2 = create_script_view(scene_2)
      p_2 = create_script_piece(scene_2, "SEQ TWO BODY")
      scvv_2 = create_script_vv(scv_2, 1, p_2)

      seq_2 = create_sequence(story, "Sequence Two", "sequence-two")
      seq_view_2 = create_sequence_view(story, seq_2)
      seq_vv_2 = create_sequence_vv(seq_view_2, 1, [pin(:script_vv, scvv_2)])
      bump_script_vv(scv_2, 2, create_script_piece(scene_2, "SEQ TWO BODY V2"))

      # ── a story-wide stale script_vv (not region-bound) ──────────────────────
      scene_3 = create_scene(story, "Scene Three", "INT. WIDE - DAY")
      scv_3 = create_script_view(scene_3)
      p_3 = create_script_piece(scene_3, "WIDE BODY")
      scvv_3 = create_script_vv(scv_3, 1, p_3)
      bump_script_piece(scene_3, "WIDE BODY V2")

      %{
        story: story,
        other_story: other_story,
        raw_token: raw_token,
        seq_1: seq_1,
        seq_2: seq_2,
        seq_vv_1: seq_vv_1,
        seq_vv_2: seq_vv_2,
        scvv_3: scvv_3
      }
    end

    test "echoes sequence_id and prunes sequence_vv entries to that region", %{
      conn: conn,
      story: story,
      raw_token: raw_token,
      seq_1: seq_1,
      seq_vv_1: seq_vv_1,
      seq_vv_2: seq_vv_2,
      scvv_3: scvv_3
    } do
      body =
        conn
        |> get_staleness(story, raw_token, %{sequence_id: seq_1.id})
        |> json_response(200)

      assert body["story_id"] == story.id
      assert body["sequence_id"] == seq_1.id

      ids = MapSet.new(body["view_versions"], & &1["id"])

      # region 1's sequence_vv survives; region 2's is pruned.
      assert MapSet.member?(ids, seq_vv_1.id)
      refute MapSet.member?(ids, seq_vv_2.id)

      # the story-wide script_vv passes through the sequence filter.
      assert MapSet.member?(ids, scvv_3.id)
    end

    test "unknown sequence_id returns 404", %{
      conn: conn,
      story: story,
      raw_token: raw_token
    } do
      conn =
        get_staleness(conn, story, raw_token, %{
          sequence_id: "00000000-0000-0000-0000-000000000000"
        })

      assert json_response(conn, 404)["error"] == "sequence not found"
    end

    test "a sequence in another story returns 404", %{
      conn: conn,
      story: story,
      other_story: other_story,
      raw_token: raw_token
    } do
      foreign = create_sequence(other_story, "Foreign", "foreign-seq")

      conn = get_staleness(conn, story, raw_token, %{sequence_id: foreign.id})

      assert json_response(conn, 404)["error"] == "sequence not found"
    end
  end
end
