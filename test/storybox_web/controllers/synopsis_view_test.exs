defmodule StoryboxWeb.SynopsisViewTest do
  use StoryboxWeb.ConnCase

  alias Storybox.Accounts.ApiToken

  require Ash.Query

  setup do
    {:ok, user} =
      Storybox.Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "synopsis_view_test@example.com",
        password: "password123!",
        password_confirmation: "password123!"
      })
      |> Ash.create()

    {:ok, story} =
      Storybox.Stories.Story
      |> Ash.Changeset.for_create(:create, %{title: "Synopsis Test Story", user_id: user.id})
      |> Ash.create()

    {:ok, other_story} =
      Storybox.Stories.Story
      |> Ash.Changeset.for_create(:create, %{title: "Other Story", user_id: user.id})
      |> Ash.create()

    {:ok, raw_token, _} = ApiToken.generate(%{story_id: story.id, user_id: user.id})

    %{user: user, story: story, other_story: other_story, raw_token: raw_token}
  end

  defp authed(conn, raw_token) do
    put_req_header(conn, "authorization", "Bearer #{raw_token}")
  end

  defp create_sequence(story, name, slug) do
    {:ok, seq} =
      Storybox.Stories.Sequence
      |> Ash.Changeset.for_create(:create, %{story_id: story.id, name: name, slug: slug})
      |> Ash.create(authorize?: false)

    seq
  end

  defp create_synopsis_piece(story, sequence, content) do
    {:ok, piece} =
      Storybox.Stories.SynopsisPiece
      |> Ash.ActionInput.for_action(:create_version, %{
        story_id: story.id,
        sequence_id: sequence.id,
        content: content
      })
      |> Ash.run_action(authorize?: false)

    piece
  end

  # Ensures the SynopsisView and cuts a fresh ViewVersion from the live spine.
  defp cut_synopsis(story) do
    {:ok, sv} =
      Storybox.Stories.SynopsisView
      |> Ash.ActionInput.for_action(:ensure_for_story, %{story_id: story.id})
      |> Ash.run_action(authorize?: false)

    {:ok, vv} =
      Storybox.Stories.SynopsisViewVersion
      |> Ash.ActionInput.for_action(:cut, %{synopsis_view_id: sv.id})
      |> Ash.run_action(authorize?: false)

    {sv, vv}
  end

  defp story_spine(story) do
    Storybox.Stories.StorySpine
    |> Ash.Query.filter(story_id == ^story.id)
    |> Ash.read_one!(authorize?: false)
  end

  describe "GET /api/stories/:story_id/views/synopsis" do
    test "returns 404 when no SynopsisView exists for the story", %{
      conn: conn,
      story: story,
      raw_token: raw_token
    } do
      # Remove the bootstrap SV (and its SVV) to reach the "no synopsis" state
      sv =
        Storybox.Stories.SynopsisView
        |> Ash.Query.filter(story_id == ^story.id)
        |> Ash.read_one!(authorize?: false)

      Storybox.Stories.SynopsisViewVersion
      |> Ash.Query.filter(synopsis_view_id == ^sv.id)
      |> Ash.read!(authorize?: false)
      |> Enum.each(&Ash.destroy!(&1, authorize?: false))

      Ash.destroy!(sv, authorize?: false)

      conn =
        conn
        |> authed(raw_token)
        |> get("/api/stories/#{story.id}/views/synopsis")

      assert json_response(conn, 404)["error"] == "no synopsis found"
    end

    test "returns 404 when SynopsisView exists but has no versions", %{
      conn: conn,
      story: story,
      raw_token: raw_token
    } do
      # Remove the bootstrap SVV to reach the "no versions" state
      sv =
        Storybox.Stories.SynopsisView
        |> Ash.Query.filter(story_id == ^story.id)
        |> Ash.read_one!(authorize?: false)

      Storybox.Stories.SynopsisViewVersion
      |> Ash.Query.filter(synopsis_view_id == ^sv.id)
      |> Ash.read!(authorize?: false)
      |> Enum.each(&Ash.destroy!(&1, authorize?: false))

      conn =
        conn
        |> authed(raw_token)
        |> get("/api/stories/#{story.id}/views/synopsis")

      assert json_response(conn, 404)["error"] == "no synopsis found"
    end

    test "returns latest version metadata when SynopsisViewVersions exist", %{
      conn: conn,
      story: story,
      raw_token: raw_token
    } do
      {:ok, sv} =
        Storybox.Stories.SynopsisView
        |> Ash.ActionInput.for_action(:ensure_for_story, %{story_id: story.id})
        |> Ash.run_action()

      # Bootstrap already created v1; create v2 to test that the latest is returned
      {:ok, _vv2} =
        Storybox.Stories.SynopsisViewVersion
        |> Ash.Changeset.for_create(:create, %{synopsis_view_id: sv.id, version_number: 2})
        |> Ash.create()

      conn =
        conn
        |> authed(raw_token)
        |> get("/api/stories/#{story.id}/views/synopsis")

      assert %{
               "story_id" => story_id,
               "synopsis_view_id" => synopsis_view_id,
               "version_number" => version_number,
               "inserted_at" => _inserted_at
             } = json_response(conn, 200)

      assert story_id == story.id
      assert synopsis_view_id == sv.id
      assert version_number == 2
    end

    test "returns 403 when token is scoped to a different story", %{
      conn: conn,
      other_story: other_story,
      raw_token: raw_token
    } do
      conn =
        conn
        |> authed(raw_token)
        |> get("/api/stories/#{other_story.id}/views/synopsis")

      assert json_response(conn, 403)["error"] == "forbidden"
    end
  end

  describe "GET /api/stories/:story_id/views/synopsis — resolved content" do
    setup %{story: story} do
      seq_a = create_sequence(story, "Act One", "act-one")
      seq_b = create_sequence(story, "Act Two", "act-two")
      %{seq_a: seq_a, seq_b: seq_b}
    end

    test "resolves each segment's SynopsisPiece content in live spine order", %{
      conn: conn,
      story: story,
      raw_token: raw_token,
      seq_a: seq_a,
      seq_b: seq_b
    } do
      create_synopsis_piece(story, seq_a, "Act one synopsis.")
      create_synopsis_piece(story, seq_b, "Act two synopsis.")
      {sv, vv} = cut_synopsis(story)

      conn =
        conn
        |> authed(raw_token)
        |> get("/api/stories/#{story.id}/views/synopsis")

      body = json_response(conn, 200)

      assert body["story_id"] == story.id
      assert body["synopsis_view_id"] == sv.id
      assert body["version_number"] == vv.version_number
      assert body["resolved"] == true
      assert body["unresolvable"] == []

      assert body["paragraphs"] == [
               %{"sequence_id" => seq_a.id, "content" => "Act one synopsis."},
               %{"sequence_id" => seq_b.id, "content" => "Act two synopsis."}
             ]
    end

    test "records nil-pin segments in unresolvable and omits them from paragraphs", %{
      conn: conn,
      story: story,
      raw_token: raw_token,
      seq_a: seq_a,
      seq_b: seq_b
    } do
      # seq_a has a piece; seq_b has none → a nil-pin segment in the cut VV.
      create_synopsis_piece(story, seq_a, "Act one synopsis.")
      cut_synopsis(story)

      conn =
        conn
        |> authed(raw_token)
        |> get("/api/stories/#{story.id}/views/synopsis")

      body = json_response(conn, 200)

      assert body["resolved"] == false

      assert body["paragraphs"] == [
               %{"sequence_id" => seq_a.id, "content" => "Act one synopsis."}
             ]

      assert [%{"sequence_id" => unresolved_seq_id, "position" => position}] =
               body["unresolvable"]

      assert unresolved_seq_id == seq_b.id
      assert is_integer(position)
    end

    test "returns 503 when a pinned SynopsisPiece's content is unavailable", %{
      conn: conn,
      story: story,
      raw_token: raw_token,
      seq_a: seq_a
    } do
      # A SynopsisPiece pointing at a non-existent storage object becomes the
      # latest version the cut pins for seq_a.
      {:ok, _bad_piece} =
        Storybox.Stories.SynopsisPiece
        |> Ash.Changeset.for_create(:create, %{
          story_id: story.id,
          sequence_id: seq_a.id,
          content_uri: "storybox://synopsis/#{seq_a.id}/v999_missing.md",
          version_number: 999
        })
        |> Ash.create(authorize?: false)

      cut_synopsis(story)

      conn =
        conn
        |> authed(raw_token)
        |> get("/api/stories/#{story.id}/views/synopsis")

      assert json_response(conn, 503)["error"] == "content unavailable"
    end

    test "returns paragraphs in live spine order after the spine is reordered post-cut", %{
      conn: conn,
      story: story,
      raw_token: raw_token,
      seq_a: seq_a,
      seq_b: seq_b
    } do
      create_synopsis_piece(story, seq_a, "Act one synopsis.")
      create_synopsis_piece(story, seq_b, "Act two synopsis.")
      cut_synopsis(story)

      # Move seq_b ahead of seq_a on the live spine, after the VV was cut.
      spine = story_spine(story)

      {:ok, _} =
        Storybox.Stories.StorySpine
        |> Ash.ActionInput.for_action(:reorder_entry, %{
          story_spine_id: spine.id,
          sequence_id: seq_b.id,
          new_position: 1
        })
        |> Ash.run_action(authorize?: false)

      conn =
        conn
        |> authed(raw_token)
        |> get("/api/stories/#{story.id}/views/synopsis")

      body = json_response(conn, 200)

      assert body["paragraphs"] == [
               %{"sequence_id" => seq_b.id, "content" => "Act two synopsis."},
               %{"sequence_id" => seq_a.id, "content" => "Act one synopsis."}
             ]
    end

    test "skips segments whose sequence is no longer on the live spine", %{
      conn: conn,
      story: story,
      raw_token: raw_token,
      seq_a: seq_a,
      seq_b: seq_b
    } do
      create_synopsis_piece(story, seq_a, "Act one synopsis.")
      create_synopsis_piece(story, seq_b, "Act two synopsis.")
      cut_synopsis(story)

      # Remove seq_b from the spine after the cut — its segment is now orphaned.
      spine = story_spine(story)

      {:ok, _} =
        Storybox.Stories.StorySpine
        |> Ash.ActionInput.for_action(:remove_entry, %{
          story_spine_id: spine.id,
          sequence_id: seq_b.id
        })
        |> Ash.run_action(authorize?: false)

      conn =
        conn
        |> authed(raw_token)
        |> get("/api/stories/#{story.id}/views/synopsis")

      body = json_response(conn, 200)

      assert body["resolved"] == true
      assert body["unresolvable"] == []

      assert body["paragraphs"] == [
               %{"sequence_id" => seq_a.id, "content" => "Act one synopsis."}
             ]
    end

    test "returns 403 when token is scoped to a different story", %{
      conn: conn,
      other_story: other_story,
      raw_token: raw_token
    } do
      conn =
        conn
        |> authed(raw_token)
        |> get("/api/stories/#{other_story.id}/views/synopsis")

      assert json_response(conn, 403)["error"] == "forbidden"
    end
  end
end
