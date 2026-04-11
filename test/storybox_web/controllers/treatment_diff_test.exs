defmodule StoryboxWeb.TreatmentDiffTest do
  use StoryboxWeb.ConnCase

  alias Storybox.Accounts.ApiToken

  setup do
    {:ok, user} =
      Storybox.Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "diff_test@example.com",
        password: "password123!",
        password_confirmation: "password123!"
      })
      |> Ash.create()

    {:ok, story} =
      Storybox.Stories.Story
      |> Ash.Changeset.for_create(:create, %{
        title: "Diff Test Story",
        through_lines: ["courage"],
        user_id: user.id
      })
      |> Ash.create()

    {:ok, other_story} =
      Storybox.Stories.Story
      |> Ash.Changeset.for_create(:create, %{title: "Other Story", user_id: user.id})
      |> Ash.create()

    # v1 — "Act II: The conflict grows." will appear as a del
    {:ok, _sv1} =
      Storybox.Stories.SynopsisVersion
      |> Ash.ActionInput.for_action(:create_version, %{
        story_id: story.id,
        content: "Act I: The hero begins.\nAct II: The conflict grows."
      })
      |> Ash.run_action()

    # v2 — replaces the Act II line, adds Act III
    {:ok, _sv2} =
      Storybox.Stories.SynopsisVersion
      |> Ash.ActionInput.for_action(:create_version, %{
        story_id: story.id,
        content: "Act I: The hero begins.\nAct II: The conflict escalates.\nAct III: Resolution."
      })
      |> Ash.run_action()

    # "Opening" — has a current approved version (upstream_status: :current)
    {:ok, opening} =
      Storybox.Stories.SequencePiece
      |> Ash.Changeset.for_create(:create, %{
        title: "Opening",
        act: "Act I",
        position: 1,
        story_id: story.id
      })
      |> Ash.create(authorize?: false)

    {:ok, opening_v} =
      Storybox.Stories.SequencePiece
      |> Ash.ActionInput.for_action(:create_version, %{
        sequence_piece_id: opening.id,
        content: "EXT. PARK - DAY\n\nThe hero walks alone."
      })
      |> Ash.run_action(authorize?: false)

    {:ok, _} =
      opening
      |> Ash.Changeset.for_update(:approve_version, %{version_id: opening_v.id})
      |> Ash.update(authorize?: false)

    # "Midpoint" — has a stale approved version (upstream_status: :stale)
    {:ok, midpoint} =
      Storybox.Stories.SequencePiece
      |> Ash.Changeset.for_create(:create, %{
        title: "Midpoint",
        act: "Act II",
        position: 1,
        story_id: story.id
      })
      |> Ash.create(authorize?: false)

    {:ok, stale_v} =
      Storybox.Stories.SequenceVersion
      |> Ash.Changeset.for_create(:create, %{
        sequence_piece_id: midpoint.id,
        content_uri: "storybox://stories/#{story.id}/sequences/#{midpoint.id}/v1.fountain",
        version_number: 1,
        upstream_status: :stale,
        weights: %{}
      })
      |> Ash.create(authorize?: false)

    {:ok, _} =
      midpoint
      |> Ash.Changeset.for_update(:approve_version, %{version_id: stale_v.id})
      |> Ash.update(authorize?: false)

    # "Draft" — no approved version
    {:ok, _draft} =
      Storybox.Stories.SequencePiece
      |> Ash.Changeset.for_create(:create, %{
        title: "Draft",
        act: "Act I",
        position: 2,
        story_id: story.id
      })
      |> Ash.create(authorize?: false)

    {:ok, raw_token, _} = ApiToken.generate(%{story_id: story.id, user_id: user.id})

    %{user: user, story: story, other_story: other_story, raw_token: raw_token}
  end

  defp authed(conn, raw_token) do
    put_req_header(conn, "authorization", "Bearer #{raw_token}")
  end

  describe "GET /api/stories/:story_id/views/treatment/diff" do
    test "returns 200 with story_id, from_version, to_version", %{
      conn: conn,
      story: story,
      raw_token: raw_token
    } do
      conn =
        conn
        |> authed(raw_token)
        |> get("/api/stories/#{story.id}/views/treatment/diff?from=1&to=2")

      body = json_response(conn, 200)
      assert body["story_id"] == story.id
      assert body["from_version"] == 1
      assert body["to_version"] == 2
    end

    test "synopsis_diff eq entry contains unchanged first line", %{
      conn: conn,
      story: story,
      raw_token: raw_token
    } do
      conn =
        conn
        |> authed(raw_token)
        |> get("/api/stories/#{story.id}/views/treatment/diff?from=1&to=2")

      diff = json_response(conn, 200)["synopsis_diff"]
      eq_entry = Enum.find(diff, &(&1["op"] == "eq"))
      assert eq_entry != nil
      assert "Act I: The hero begins." in eq_entry["lines"]
    end

    test "synopsis_diff del entry contains removed line", %{
      conn: conn,
      story: story,
      raw_token: raw_token
    } do
      conn =
        conn
        |> authed(raw_token)
        |> get("/api/stories/#{story.id}/views/treatment/diff?from=1&to=2")

      diff = json_response(conn, 200)["synopsis_diff"]
      del_entry = Enum.find(diff, &(&1["op"] == "del"))
      assert del_entry != nil
      assert "Act II: The conflict grows." in del_entry["lines"]
    end

    test "synopsis_diff ins entries contain added lines", %{
      conn: conn,
      story: story,
      raw_token: raw_token
    } do
      conn =
        conn
        |> authed(raw_token)
        |> get("/api/stories/#{story.id}/views/treatment/diff?from=1&to=2")

      diff = json_response(conn, 200)["synopsis_diff"]
      ins_lines = diff |> Enum.filter(&(&1["op"] == "ins")) |> Enum.flat_map(& &1["lines"])
      assert "Act II: The conflict escalates." in ins_lines
      assert "Act III: Resolution." in ins_lines
    end

    test "sequences.unaffected contains Opening with upstream_status current", %{
      conn: conn,
      story: story,
      raw_token: raw_token
    } do
      conn =
        conn
        |> authed(raw_token)
        |> get("/api/stories/#{story.id}/views/treatment/diff?from=1&to=2")

      unaffected = json_response(conn, 200)["sequences"]["unaffected"]
      assert length(unaffected) == 1
      opening = hd(unaffected)
      assert opening["title"] == "Opening"
      assert opening["approved_version"]["upstream_status"] == "current"
    end

    test "sequences.affected contains Midpoint with upstream_status stale", %{
      conn: conn,
      story: story,
      raw_token: raw_token
    } do
      conn =
        conn
        |> authed(raw_token)
        |> get("/api/stories/#{story.id}/views/treatment/diff?from=1&to=2")

      affected = json_response(conn, 200)["sequences"]["affected"]
      assert length(affected) == 1
      midpoint = hd(affected)
      assert midpoint["title"] == "Midpoint"
      assert midpoint["approved_version"]["upstream_status"] == "stale"
    end

    test "sequences.new contains Draft with null approved_version", %{
      conn: conn,
      story: story,
      raw_token: raw_token
    } do
      conn =
        conn
        |> authed(raw_token)
        |> get("/api/stories/#{story.id}/views/treatment/diff?from=1&to=2")

      new_seqs = json_response(conn, 200)["sequences"]["new"]
      assert length(new_seqs) == 1
      draft = hd(new_seqs)
      assert draft["title"] == "Draft"
      assert draft["approved_version"] == nil
    end

    test "sequence entries include id, title, act, position, approved_version fields", %{
      conn: conn,
      story: story,
      raw_token: raw_token
    } do
      conn =
        conn
        |> authed(raw_token)
        |> get("/api/stories/#{story.id}/views/treatment/diff?from=1&to=2")

      sequences = json_response(conn, 200)["sequences"]
      all = sequences["affected"] ++ sequences["unaffected"] ++ sequences["new"]

      for seq <- all do
        assert Map.has_key?(seq, "id")
        assert Map.has_key?(seq, "title")
        assert Map.has_key?(seq, "act")
        assert Map.has_key?(seq, "position")
        assert Map.has_key?(seq, "approved_version")
      end
    end

    test "returns 400 when from param is missing", %{
      conn: conn,
      story: story,
      raw_token: raw_token
    } do
      conn =
        conn
        |> authed(raw_token)
        |> get("/api/stories/#{story.id}/views/treatment/diff?to=2")

      assert json_response(conn, 400)["error"] == "from and to version numbers are required"
    end

    test "returns 400 when to param is missing", %{
      conn: conn,
      story: story,
      raw_token: raw_token
    } do
      conn =
        conn
        |> authed(raw_token)
        |> get("/api/stories/#{story.id}/views/treatment/diff?from=1")

      assert json_response(conn, 400)["error"] == "from and to version numbers are required"
    end

    test "returns 400 when from is not a valid integer", %{
      conn: conn,
      story: story,
      raw_token: raw_token
    } do
      conn =
        conn
        |> authed(raw_token)
        |> get("/api/stories/#{story.id}/views/treatment/diff?from=abc&to=2")

      assert json_response(conn, 400)["error"] == "from and to must be integers"
    end

    test "returns 404 when from version does not exist", %{
      conn: conn,
      story: story,
      raw_token: raw_token
    } do
      conn =
        conn
        |> authed(raw_token)
        |> get("/api/stories/#{story.id}/views/treatment/diff?from=999&to=2")

      assert json_response(conn, 404)["error"] == "synopsis version not found"
    end

    test "returns 404 when to version does not exist", %{
      conn: conn,
      story: story,
      raw_token: raw_token
    } do
      conn =
        conn
        |> authed(raw_token)
        |> get("/api/stories/#{story.id}/views/treatment/diff?from=1&to=999")

      assert json_response(conn, 404)["error"] == "synopsis version not found"
    end

    test "returns 403 when token is scoped to a different story", %{
      conn: conn,
      other_story: other_story,
      raw_token: raw_token
    } do
      conn =
        conn
        |> authed(raw_token)
        |> get("/api/stories/#{other_story.id}/views/treatment/diff?from=1&to=2")

      assert json_response(conn, 403)["error"] == "forbidden"
    end
  end
end
