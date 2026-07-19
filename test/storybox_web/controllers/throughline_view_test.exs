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

  defp segment_for_vv(vv, pin_type) do
    %{
      "pin_id" => vv.id,
      "pin_type" => pin_type,
      "pin_version_at_creation" => vv.version_number
    }
  end

  # Ensures the ThroughlineView and cuts a fresh top ViewVersion with the given
  # explicit segment list.
  defp cut_throughline(story, segments) do
    tv = ensure_throughline_view(story)

    {:ok, vv} =
      Storybox.Stories.ThroughlineViewVersion
      |> Ash.ActionInput.for_action(:cut, %{throughline_view_id: tv.id, segments: segments})
      |> Ash.run_action(authorize?: false)

    {tv, vv}
  end

  # Cuts a per-character through-line view version. With no explicit segments
  # the cut auto-pins that character's latest ThroughlinePiece at position 1.
  defp cut_character_throughline(story, character) do
    {:ok, view} =
      Storybox.Stories.CharacterThroughlineView
      |> Ash.ActionInput.for_action(:ensure_for_story_character, %{
        story_id: story.id,
        character_id: character.id
      })
      |> Ash.run_action(authorize?: false)

    {:ok, vv} =
      Storybox.Stories.CharacterThroughlineViewVersion
      |> Ash.ActionInput.for_action(:cut, %{character_throughline_view_id: view.id})
      |> Ash.run_action(authorize?: false)

    vv
  end

  defp cut_cast_throughline(story, segments) do
    {:ok, view} =
      Storybox.Stories.ThroughlineCastView
      |> Ash.ActionInput.for_action(:ensure_for_story, %{story_id: story.id})
      |> Ash.run_action(authorize?: false)

    {:ok, vv} =
      Storybox.Stories.ThroughlineCastViewVersion
      |> Ash.ActionInput.for_action(:cut, %{
        throughline_cast_view_id: view.id,
        segments: segments
      })
      |> Ash.run_action(authorize?: false)

    vv
  end

  # Builds the three-level harness from already-written pieces: one view version
  # per character, a cast version pinning them in the given order, and a top
  # version pinning the story arc (when given) plus the cast.
  defp build_nested_throughline(story, story_piece, characters) do
    cast_segments =
      Enum.map(characters, fn character ->
        story
        |> cut_character_throughline(character)
        |> segment_for_vv("throughline_vv")
      end)

    cast_pin =
      case cast_segments do
        [] -> []
        segs -> [segment_for_vv(cut_cast_throughline(story, segs), "throughline_cast_vv")]
      end

    story_pin = if story_piece, do: [segment_for(story_piece)], else: []

    cut_throughline(story, story_pin ++ cast_pin)
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
      _line_a = create_throughline_piece(story, char_a.id, "Alice learns to forgive.")
      _line_b = create_throughline_piece(story, char_b.id, "Bob loses everything.")

      {tv, vv} = build_nested_throughline(story, idea, [char_a, char_b])

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
      _line_a = create_throughline_piece(story, char_a.id, "Alice learns to forgive.")

      # A nil-pin entry sits in the cast stack alongside Alice's resolved line —
      # a character slot whose view version was never pinned.
      char_vv = cut_character_throughline(story, char_a)

      cast_vv =
        cut_cast_throughline(story, [
          segment_for_vv(char_vv, "throughline_vv"),
          %{"pin_id" => nil, "pin_type" => nil, "pin_version_at_creation" => nil}
        ])

      cut_throughline(story, [
        segment_for(idea),
        segment_for_vv(cast_vv, "throughline_cast_vv")
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
      _line_a = create_throughline_piece(story, char_a.id, "Alice learns to forgive.")

      build_nested_throughline(story, nil, [char_a])

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

      build_nested_throughline(story, idea, [])

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
