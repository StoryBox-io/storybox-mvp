defmodule StoryboxWeb.ThroughlineViewTest do
  use StoryboxWeb.ConnCase

  alias Storybox.Accounts.ApiToken

  require Ash.Query

  setup do
    {:ok, user} =
      Storybox.Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "throughline_view_test@example.com",
        password: "password123!",
        password_confirmation: "password123!"
      })
      |> Ash.create()

    {:ok, story} =
      Storybox.Stories.Story
      |> Ash.Changeset.for_create(:create, %{title: "Through-line Test Story", user_id: user.id})
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

  defp create_character(story, name) do
    {:ok, character} =
      Storybox.Stories.Character
      |> Ash.Changeset.for_create(:create, %{story_id: story.id, name: name})
      |> Ash.create(authorize?: false)

    character
  end

  # Writes a ThroughlinePiece version. A nil character_id is the Story's
  # controlling idea; a set character_id is that character's through-line.
  defp create_throughline_piece(story, character_id, content) do
    {:ok, piece} =
      Storybox.Stories.ThroughlinePiece
      |> Ash.ActionInput.for_action(:create_version, %{
        story_id: story.id,
        character_id: character_id,
        content: content
      })
      |> Ash.run_action(authorize?: false)

    piece
  end

  defp ensure_throughline_view(story) do
    {:ok, tv} =
      Storybox.Stories.ThroughlineView
      |> Ash.ActionInput.for_action(:ensure_for_story, %{story_id: story.id})
      |> Ash.run_action(authorize?: false)

    tv
  end

  defp segment_for(piece) do
    %{
      "pin_id" => piece.id,
      "pin_type" => "throughline_piece",
      "pin_version_at_creation" => piece.version_number
    }
  end

  # Ensures the ThroughlineView and cuts a fresh ViewVersion with the given
  # explicit segment list (the harness has no spine to derive segments from).
  defp cut_throughline(story, segments) do
    tv = ensure_throughline_view(story)

    {:ok, vv} =
      Storybox.Stories.ThroughlineViewVersion
      |> Ash.ActionInput.for_action(:cut, %{throughline_view_id: tv.id, segments: segments})
      |> Ash.run_action(authorize?: false)

    {tv, vv}
  end

  describe "GET /api/stories/:story_id/views/throughline" do
    test "returns 404 when no ThroughlineView exists for the story", %{
      conn: conn,
      story: story,
      raw_token: raw_token
    } do
      # A fresh story has no ThroughlineView (bootstrap does not create one).
      conn =
        conn
        |> authed(raw_token)
        |> get("/api/stories/#{story.id}/views/throughline")

      assert json_response(conn, 404)["error"] == "no through-line found"
    end

    test "returns 404 when ThroughlineView exists but has no versions", %{
      conn: conn,
      story: story,
      raw_token: raw_token
    } do
      ensure_throughline_view(story)

      conn =
        conn
        |> authed(raw_token)
        |> get("/api/stories/#{story.id}/views/throughline")

      assert json_response(conn, 404)["error"] == "no through-line found"
    end

    test "returns 403 when token is scoped to a different story", %{
      conn: conn,
      other_story: other_story,
      raw_token: raw_token
    } do
      conn =
        conn
        |> authed(raw_token)
        |> get("/api/stories/#{other_story.id}/views/throughline")

      assert json_response(conn, 403)["error"] == "forbidden"
    end
  end

  describe "GET /api/stories/:story_id/views/throughline — resolved content" do
    test "resolves the controlling idea and one through-line per character", %{
      conn: conn,
      story: story,
      raw_token: raw_token
    } do
      char_a = create_character(story, "Alice")
      char_b = create_character(story, "Bob")

      idea = create_throughline_piece(story, nil, "The cost of revenge.")
      line_a = create_throughline_piece(story, char_a.id, "Alice learns to forgive.")
      line_b = create_throughline_piece(story, char_b.id, "Bob loses everything.")

      {tv, vv} =
        cut_throughline(story, [segment_for(idea), segment_for(line_a), segment_for(line_b)])

      conn =
        conn
        |> authed(raw_token)
        |> get("/api/stories/#{story.id}/views/throughline")

      body = json_response(conn, 200)

      assert body["story_id"] == story.id
      assert body["throughline_view_id"] == tv.id
      assert body["version_number"] == vv.version_number
      assert body["resolved"] == true
      assert body["unresolvable"] == []
      assert body["controlling_idea"] == "The cost of revenge."

      assert body["through_lines"] == [
               %{"character_id" => char_a.id, "content" => "Alice learns to forgive."},
               %{"character_id" => char_b.id, "content" => "Bob loses everything."}
             ]
    end

    test "records nil-pin segments in unresolvable and omits them from content", %{
      conn: conn,
      story: story,
      raw_token: raw_token
    } do
      char_a = create_character(story, "Alice")
      idea = create_throughline_piece(story, nil, "The cost of revenge.")
      line_a = create_throughline_piece(story, char_a.id, "Alice learns to forgive.")

      # A nil-pin segment sits between the two resolved pieces.
      {_tv, _vv} =
        cut_throughline(story, [
          segment_for(idea),
          %{"pin_id" => nil, "pin_type" => nil, "pin_version_at_creation" => nil},
          segment_for(line_a)
        ])

      conn =
        conn
        |> authed(raw_token)
        |> get("/api/stories/#{story.id}/views/throughline")

      body = json_response(conn, 200)

      assert body["resolved"] == false
      assert body["controlling_idea"] == "The cost of revenge."

      assert body["through_lines"] == [
               %{"character_id" => char_a.id, "content" => "Alice learns to forgive."}
             ]

      assert [%{"position" => position}] = body["unresolvable"]
      assert is_integer(position)
    end

    test "returns 503 when a pinned ThroughlinePiece's content is unavailable", %{
      conn: conn,
      story: story,
      raw_token: raw_token
    } do
      # A ThroughlinePiece pointing at a non-existent storage object.
      {:ok, bad_piece} =
        Storybox.Stories.ThroughlinePiece
        |> Ash.Changeset.for_create(:create, %{
          story_id: story.id,
          character_id: nil,
          content_uri:
            "storybox://stories/#{story.id}/throughlines/controlling_idea/v999_missing",
          version_number: 999
        })
        |> Ash.create(authorize?: false)

      cut_throughline(story, [segment_for(bad_piece)])

      conn =
        conn
        |> authed(raw_token)
        |> get("/api/stories/#{story.id}/views/throughline")

      assert json_response(conn, 503)["error"] == "content unavailable"
    end

    test "controlling_idea is nil and through_lines empty when only a character line is pinned",
         %{conn: conn, story: story, raw_token: raw_token} do
      char_a = create_character(story, "Alice")
      line_a = create_throughline_piece(story, char_a.id, "Alice learns to forgive.")

      cut_throughline(story, [segment_for(line_a)])

      conn =
        conn
        |> authed(raw_token)
        |> get("/api/stories/#{story.id}/views/throughline")

      body = json_response(conn, 200)

      assert body["resolved"] == true
      assert body["controlling_idea"] == nil

      assert body["through_lines"] == [
               %{"character_id" => char_a.id, "content" => "Alice learns to forgive."}
             ]
    end

    test "through_lines is empty when only the controlling idea is pinned", %{
      conn: conn,
      story: story,
      raw_token: raw_token
    } do
      idea = create_throughline_piece(story, nil, "The cost of revenge.")

      cut_throughline(story, [segment_for(idea)])

      conn =
        conn
        |> authed(raw_token)
        |> get("/api/stories/#{story.id}/views/throughline")

      body = json_response(conn, 200)

      assert body["resolved"] == true
      assert body["controlling_idea"] == "The cost of revenge."
      assert body["through_lines"] == []
    end
  end
end
