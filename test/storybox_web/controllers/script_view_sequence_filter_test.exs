defmodule StoryboxWeb.ScriptViewSequenceFilterTest do
  use StoryboxWeb.ConnCase

  import StoryboxWeb.ScriptViewHelpers

  alias Storybox.Accounts.ApiToken
  alias Storybox.Stories.Segment

  require Ash.Query

  # Builds a story whose StoryScriptViewVersion pins two sequences, each with
  # its own scene chain. The story_script_vv Segments carry `sequence_id` (as a
  # real cut writes), so the `?sequence_id` filter can scope the assembled script
  # to a single region.
  #
  #   StoryScriptVV ssvv
  #     seg(sequence_id: seq_1) → seq_vv_1 → Scene One
  #     seg(sequence_id: seq_2) → seq_vv_2 → Scene Two
  setup do
    {:ok, user} =
      Storybox.Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "script_view_seq_filter_test@example.com",
        password: "password123!",
        password_confirmation: "password123!"
      })
      |> Ash.create()

    story = create_story(user, "Region Filter Story")
    other_story = create_story(user, "Other Story")

    {:ok, raw_token, _} = ApiToken.generate(%{story_id: story.id, user_id: user.id})

    # ── region 1 ─────────────────────────────────────────────────────────────
    scene_1 = create_scene(story, "Scene One", "INT. SEQ ONE - DAY")
    scv_1 = create_script_view(scene_1)
    p_1 = create_script_piece(scene_1, "SEQ ONE BODY")
    scvv_1 = create_script_vv(scv_1, 1, p_1)

    seq_1 = create_sequence(story, "Sequence One", "sequence-one")
    seq_view_1 = create_sequence_view(story, seq_1)
    seq_vv_1 = create_sequence_vv(seq_view_1, 1, [pin(:script_vv, scvv_1)])

    # ── region 2 ─────────────────────────────────────────────────────────────
    scene_2 = create_scene(story, "Scene Two", "INT. SEQ TWO - DAY")
    scv_2 = create_script_view(scene_2)
    p_2 = create_script_piece(scene_2, "SEQ TWO BODY")
    scvv_2 = create_script_vv(scv_2, 1, p_2)

    seq_2 = create_sequence(story, "Sequence Two", "sequence-two")
    seq_view_2 = create_sequence_view(story, seq_2)
    seq_vv_2 = create_sequence_vv(seq_view_2, 1, [pin(:script_vv, scvv_2)])

    # ── StoryScriptVV with sequence-tagged segments ──────────────────────────
    ssv = create_story_script_view(story)

    {:ok, ssvv} =
      Storybox.Stories.StoryScriptViewVersion
      |> Ash.Changeset.for_create(:create, %{story_script_view_id: ssv.id, version_number: 1})
      |> Ash.create(authorize?: false)

    create_story_script_segment(ssvv.id, 1, seq_1.id, seq_vv_1)
    create_story_script_segment(ssvv.id, 2, seq_2.id, seq_vv_2)

    %{
      user: user,
      story: story,
      other_story: other_story,
      raw_token: raw_token,
      seq_1: seq_1,
      seq_2: seq_2,
      ssvv: ssvv
    }
  end

  # A story_script_vv Segment that carries both its Sequence and its pin — the
  # shared helper does not set `sequence_id`, which this filter relies on.
  defp create_story_script_segment(ssvv_id, position, sequence_id, seq_vv) do
    {:ok, seg} =
      Segment
      |> Ash.Changeset.for_create(:create, %{
        view_version_id: ssvv_id,
        view_version_type: :story_script_vv,
        position: position,
        sequence_id: sequence_id,
        pin_id: seq_vv.id,
        pin_type: :sequence_vv,
        pin_version_at_creation: seq_vv.version_number
      })
      |> Ash.create(authorize?: false)

    seg
  end

  defp authed(conn, raw_token), do: put_req_header(conn, "authorization", "Bearer #{raw_token}")

  defp get_script(conn, story, raw_token, params) do
    query = URI.encode_query(params)
    conn |> authed(raw_token) |> get("/api/stories/#{story.id}/views/script?#{query}")
  end

  describe "GET /views/script?sequence_id — JSON" do
    test "without a filter assembles every region in spine order", %{
      conn: conn,
      story: story,
      raw_token: raw_token
    } do
      body = conn |> get_script(story, raw_token, %{mode: "latest"}) |> json_response(200)

      assert body["resolved"] == true

      assert body["content"] ==
               "INT. SEQ ONE - DAY\n\nSEQ ONE BODY\n\nINT. SEQ TWO - DAY\n\nSEQ TWO BODY"
    end

    test "?sequence_id scopes the assembled content to that region", %{
      conn: conn,
      story: story,
      raw_token: raw_token,
      seq_2: seq_2
    } do
      body =
        conn
        |> get_script(story, raw_token, %{mode: "latest", sequence_id: seq_2.id})
        |> json_response(200)

      assert body["resolved"] == true
      assert body["content"] == "INT. SEQ TWO - DAY\n\nSEQ TWO BODY"
    end

    test "?sequence_id for a sequence in another story returns 404", %{
      conn: conn,
      story: story,
      other_story: other_story,
      raw_token: raw_token
    } do
      other_seq = create_sequence(other_story, "Foreign", "foreign-seq")

      conn =
        get_script(conn, story, raw_token, %{mode: "latest", sequence_id: other_seq.id})

      assert json_response(conn, 404)["error"] == "sequence not found"
    end

    test "malformed ?sequence_id returns 404", %{
      conn: conn,
      story: story,
      raw_token: raw_token
    } do
      conn = get_script(conn, story, raw_token, %{mode: "latest", sequence_id: "not-a-uuid"})
      assert json_response(conn, 404)["error"] == "sequence not found"
    end
  end

  describe "GET /views/script?sequence_id — fountain" do
    test "?sequence_id scopes the streamed document to that region", %{
      conn: conn,
      story: story,
      raw_token: raw_token,
      seq_1: seq_1
    } do
      body =
        conn
        |> get_script(story, raw_token, %{
          format: "fountain",
          mode: "latest",
          sequence_id: seq_1.id
        })
        |> response(200)

      assert body == "INT. SEQ ONE - DAY\n\nSEQ ONE BODY\n\n"
    end
  end
end
