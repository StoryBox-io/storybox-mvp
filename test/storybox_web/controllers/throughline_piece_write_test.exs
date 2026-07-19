defmodule StoryboxWeb.ThroughlinePieceWriteTest do
  use StoryboxWeb.ConnCase

  alias Storybox.Accounts.ApiToken

  require Ash.Query

  setup do
    {:ok, user} =
      Storybox.Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "throughline_piece_write_test@example.com",
        password: "password123!",
        password_confirmation: "password123!"
      })
      |> Ash.create()

    {:ok, story} =
      Storybox.Stories.Story
      |> Ash.Changeset.for_create(:create, %{title: "Through-line Write Story", user_id: user.id})
      |> Ash.create()

    {:ok, other_story} =
      Storybox.Stories.Story
      |> Ash.Changeset.for_create(:create, %{title: "Other Story", user_id: user.id})
      |> Ash.create()

    {:ok, char} =
      Storybox.Stories.Character
      |> Ash.Changeset.for_create(:create, %{story_id: story.id, name: "Alice"})
      |> Ash.create(authorize?: false)

    # A character on a different story — used for the cross-story 404 case.
    {:ok, other_char} =
      Storybox.Stories.Character
      |> Ash.Changeset.for_create(:create, %{story_id: other_story.id, name: "Other"})
      |> Ash.create(authorize?: false)

    {:ok, raw_token, _} = ApiToken.generate(%{story_id: story.id, user_id: user.id})

    %{
      user: user,
      story: story,
      other_story: other_story,
      char: char,
      other_char: other_char,
      raw_token: raw_token
    }
  end

  defp authed(conn, raw_token) do
    put_req_header(conn, "authorization", "Bearer #{raw_token}")
  end

  describe "POST /api/stories/:story_id/throughline/pieces" do
    test "201 — content, no character_id (controlling idea); cuts a Through-line VV", %{
      conn: conn,
      story: story,
      raw_token: token
    } do
      conn =
        conn
        |> authed(token)
        |> post("/api/stories/#{story.id}/throughline/pieces", %{
          "content" => "The cost of revenge."
        })

      body = json_response(conn, 201)
      assert body["id"]
      assert body["version_number"] == 1
      assert body["unresolvable_segments"] == []
    end

    test "201 — content with a character_id belonging to the story", %{
      conn: conn,
      story: story,
      char: char,
      raw_token: token
    } do
      conn =
        conn
        |> authed(token)
        |> post("/api/stories/#{story.id}/throughline/pieces", %{
          "content" => "Alice learns to forgive.",
          "character_id" => char.id
        })

      body = json_response(conn, 201)
      assert body["id"]
      assert body["version_number"] == 1
      assert body["unresolvable_segments"] == []
    end

    test "404 — character_id does not belong to the story", %{
      conn: conn,
      story: story,
      other_char: other_char,
      raw_token: token
    } do
      conn =
        conn
        |> authed(token)
        |> post("/api/stories/#{story.id}/throughline/pieces", %{
          "content" => "Should not be written.",
          "character_id" => other_char.id
        })

      assert json_response(conn, 404)["error"]
    end

    test "400 — missing content", %{conn: conn, story: story, raw_token: token} do
      conn =
        conn
        |> authed(token)
        |> post("/api/stories/#{story.id}/throughline/pieces", %{})

      assert json_response(conn, 400)["error"] =~ "content"
    end

    test "400 — empty content", %{conn: conn, story: story, raw_token: token} do
      conn =
        conn
        |> authed(token)
        |> post("/api/stories/#{story.id}/throughline/pieces", %{"content" => ""})

      assert json_response(conn, 400)["error"] =~ "content"
    end

    test "read-back: controlling idea then a character line populate the Through-line view", %{
      conn: conn,
      story: story,
      char: char,
      raw_token: token
    } do
      conn
      |> authed(token)
      |> post("/api/stories/#{story.id}/throughline/pieces", %{
        "content" => "The cost of revenge."
      })
      |> json_response(201)

      conn
      |> authed(token)
      |> post("/api/stories/#{story.id}/throughline/pieces", %{
        "content" => "Alice learns to forgive.",
        "character_id" => char.id
      })
      |> json_response(201)

      get_conn =
        conn
        |> authed(token)
        |> get("/api/stories/#{story.id}/views/throughline")

      body = json_response(get_conn, 200)
      assert body["controlling_idea"] == "The cost of revenge."

      assert body["through_lines"] == [
               %{"character_id" => char.id, "content" => "Alice learns to forgive."}
             ]
    end

    test "the controlling-idea lineage and a character lineage version independently", %{
      conn: conn,
      story: story,
      char: char,
      raw_token: token
    } do
      # Two controlling-idea writes (nil lineage) and one character write.
      conn
      |> authed(token)
      |> post("/api/stories/#{story.id}/throughline/pieces", %{"content" => "Idea v1."})
      |> json_response(201)

      conn
      |> authed(token)
      |> post("/api/stories/#{story.id}/throughline/pieces", %{"content" => "Idea v2."})
      |> json_response(201)

      conn
      |> authed(token)
      |> post("/api/stories/#{story.id}/throughline/pieces", %{
        "content" => "Alice line v1.",
        "character_id" => char.id
      })
      |> json_response(201)

      latest_version = fn filter ->
        Storybox.Stories.ThroughlinePiece
        |> filter.()
        |> Ash.read!(authorize?: false)
        |> Enum.map(& &1.version_number)
        |> Enum.max()
      end

      # The nil lineage reached v2; the character lineage is independently at v1.
      assert latest_version.(fn q ->
               Ash.Query.filter(q, story_id == ^story.id and is_nil(character_id))
             end) == 2

      assert latest_version.(fn q ->
               Ash.Query.filter(q, story_id == ^story.id and character_id == ^char.id)
             end) == 1
    end

    test "a write for one character leaves the other characters' views untouched", %{
      conn: conn,
      story: story,
      char: char,
      raw_token: token
    } do
      {:ok, bob} =
        Storybox.Stories.Character
        |> Ash.Changeset.for_create(:create, %{story_id: story.id, name: "Bob"})
        |> Ash.create(authorize?: false)

      write = fn body ->
        conn
        |> authed(token)
        |> post("/api/stories/#{story.id}/throughline/pieces", body)
        |> json_response(201)
      end

      char_vv_count = fn character ->
        view =
          Storybox.Stories.CharacterThroughlineView
          |> Ash.Query.filter(story_id == ^story.id and character_id == ^character.id)
          |> Ash.read_one!(authorize?: false)

        Storybox.Stories.CharacterThroughlineViewVersion
        |> Ash.Query.filter(character_throughline_view_id == ^view.id)
        |> Ash.read!(authorize?: false)
        |> length()
      end

      cast_vv_count = fn ->
        view =
          Storybox.Stories.ThroughlineCastView
          |> Ash.Query.filter(story_id == ^story.id)
          |> Ash.read_one!(authorize?: false)

        Storybox.Stories.ThroughlineCastViewVersion
        |> Ash.Query.filter(throughline_cast_view_id == ^view.id)
        |> Ash.read!(authorize?: false)
        |> length()
      end

      top_vv_count = fn ->
        view =
          Storybox.Stories.ThroughlineView
          |> Ash.Query.filter(story_id == ^story.id)
          |> Ash.read_one!(authorize?: false)

        Storybox.Stories.ThroughlineViewVersion
        |> Ash.Query.filter(throughline_view_id == ^view.id)
        |> Ash.read!(authorize?: false)
        |> length()
      end

      write.(%{"content" => "The cost of revenge."})
      write.(%{"content" => "Alice v1.", "character_id" => char.id})
      write.(%{"content" => "Bob v1.", "character_id" => bob.id})

      before = %{
        alice: char_vv_count.(char),
        bob: char_vv_count.(bob),
        cast: cast_vv_count.(),
        top: top_vv_count.()
      }

      write.(%{"content" => "Alice v2.", "character_id" => char.id})

      assert char_vv_count.(char) == before.alice + 1
      assert char_vv_count.(bob) == before.bob
      assert cast_vv_count.() == before.cast + 1
      assert top_vv_count.() == before.top + 1

      # Bob keeps his cast slot, and its position, across Alice's re-cut.
      get_body =
        conn
        |> authed(token)
        |> get("/api/stories/#{story.id}/views/throughline")
        |> json_response(200)

      assert get_body["controlling_idea"] == "The cost of revenge."

      assert get_body["through_lines"] == [
               %{"character_id" => char.id, "content" => "Alice v2."},
               %{"character_id" => bob.id, "content" => "Bob v1."}
             ]
    end

    test "a story-level write leaves the cast stack's pins intact", %{
      conn: conn,
      story: story,
      char: char,
      raw_token: token
    } do
      write = fn body ->
        conn
        |> authed(token)
        |> post("/api/stories/#{story.id}/throughline/pieces", body)
        |> json_response(201)
      end

      write.(%{"content" => "Alice v1.", "character_id" => char.id})

      cast_view =
        Storybox.Stories.ThroughlineCastView
        |> Ash.Query.filter(story_id == ^story.id)
        |> Ash.read_one!(authorize?: false)

      cast_count = fn ->
        Storybox.Stories.ThroughlineCastViewVersion
        |> Ash.Query.filter(throughline_cast_view_id == ^cast_view.id)
        |> Ash.read!(authorize?: false)
        |> length()
      end

      before = cast_count.()

      write.(%{"content" => "The cost of revenge."})

      # No new cast version — a story-arc edit is not a statement about the cast.
      assert cast_count.() == before

      body =
        conn
        |> authed(token)
        |> get("/api/stories/#{story.id}/views/throughline")
        |> json_response(200)

      assert body["controlling_idea"] == "The cost of revenge."

      assert body["through_lines"] == [
               %{"character_id" => char.id, "content" => "Alice v1."}
             ]
    end

    test "401 without token", %{conn: conn, story: story} do
      conn =
        post(conn, "/api/stories/#{story.id}/throughline/pieces", %{"content" => "x"})

      assert json_response(conn, 401)
    end
  end
end
