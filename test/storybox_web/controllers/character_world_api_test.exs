defmodule StoryboxWeb.CharacterWorldApiTest do
  use StoryboxWeb.ConnCase

  alias Storybox.Accounts.ApiToken

  require Ash.Query

  # Setup creates three stories:
  #
  # story —— char_1 (CharacterPiece v1 + CharacterView + CVV v1, content pinned)
  #        ├─ char_2 (CharacterView only, no CVV — exercises nil-content path)
  #        └─ world  (WorldPiece v1 + WorldView + WVV v1, content pinned)
  #
  # story_2 —— world_2 (WorldView only, no WVV — exercises nil-content path)
  #
  # other_story —— other_char (for character 404 test)
  #             (no World — for world 404 test)
  #
  # raw_token scoped to story; raw_token_2 to story_2; raw_token_other to other_story.

  setup do
    {:ok, user} =
      Storybox.Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "char_world_api_test@example.com",
        password: "password123!",
        password_confirmation: "password123!"
      })
      |> Ash.create()

    {:ok, story} =
      Storybox.Stories.Story
      |> Ash.Changeset.for_create(:create, %{title: "Main Story", user_id: user.id})
      |> Ash.create()

    {:ok, story_2} =
      Storybox.Stories.Story
      |> Ash.Changeset.for_create(:create, %{title: "Bare World Story", user_id: user.id})
      |> Ash.create()

    {:ok, other_story} =
      Storybox.Stories.Story
      |> Ash.Changeset.for_create(:create, %{title: "Other Story", user_id: user.id})
      |> Ash.create()

    {:ok, raw_token, _} = ApiToken.generate(%{story_id: story.id, user_id: user.id})
    {:ok, raw_token_2, _} = ApiToken.generate(%{story_id: story_2.id, user_id: user.id})
    {:ok, raw_token_other, _} = ApiToken.generate(%{story_id: other_story.id, user_id: user.id})

    # char_1: full setup (piece + view + VV)
    {:ok, char_1} =
      Storybox.Stories.Character
      |> Ash.Changeset.for_create(:create, %{name: "Akko", story_id: story.id})
      |> Ash.create(authorize?: false)

    {:ok, _cp_v1} =
      Storybox.Stories.CharacterPiece
      |> Ash.ActionInput.for_action(:create_version, %{
        character_id: char_1.id,
        content: "Akko is a witch in training."
      })
      |> Ash.run_action(authorize?: false)

    {:ok, char_view_1} =
      Storybox.Stories.CharacterView
      |> Ash.ActionInput.for_action(:ensure_for_character, %{character_id: char_1.id})
      |> Ash.run_action(authorize?: false)

    {:ok, _char_vv_1} =
      Storybox.Stories.CharacterViewVersion
      |> Ash.ActionInput.for_action(:cut, %{character_view_id: char_view_1.id})
      |> Ash.run_action(authorize?: false)

    # char_2: view exists but no piece/cut (nil-content path)
    {:ok, char_2} =
      Storybox.Stories.Character
      |> Ash.Changeset.for_create(:create, %{name: "Lotte", story_id: story.id})
      |> Ash.create(authorize?: false)

    {:ok, _char_view_2} =
      Storybox.Stories.CharacterView
      |> Ash.ActionInput.for_action(:ensure_for_character, %{character_id: char_2.id})
      |> Ash.run_action(authorize?: false)

    # other_char: for 404 test (belongs to other_story)
    {:ok, other_char} =
      Storybox.Stories.Character
      |> Ash.Changeset.for_create(:create, %{name: "Other Char", story_id: other_story.id})
      |> Ash.create(authorize?: false)

    # world: full setup (piece + view + WVV)
    {:ok, world} =
      Storybox.Stories.World
      |> Ash.Changeset.for_create(:create, %{story_id: story.id})
      |> Ash.create(authorize?: false)

    {:ok, _wp_v1} =
      Storybox.Stories.WorldPiece
      |> Ash.ActionInput.for_action(:create_version, %{
        world_id: world.id,
        content: "The witch academy world."
      })
      |> Ash.run_action(authorize?: false)

    {:ok, world_view} =
      Storybox.Stories.WorldView
      |> Ash.ActionInput.for_action(:ensure_for_world, %{world_id: world.id})
      |> Ash.run_action(authorize?: false)

    {:ok, _world_vv_1} =
      Storybox.Stories.WorldViewVersion
      |> Ash.ActionInput.for_action(:cut, %{world_view_id: world_view.id})
      |> Ash.run_action(authorize?: false)

    # world_2: WorldView only, no WVV (nil-content path)
    {:ok, world_2} =
      Storybox.Stories.World
      |> Ash.Changeset.for_create(:create, %{story_id: story_2.id})
      |> Ash.create(authorize?: false)

    {:ok, _world_view_2} =
      Storybox.Stories.WorldView
      |> Ash.ActionInput.for_action(:ensure_for_world, %{world_id: world_2.id})
      |> Ash.run_action(authorize?: false)

    %{
      story: story,
      story_2: story_2,
      other_story: other_story,
      char_1: char_1,
      char_2: char_2,
      other_char: other_char,
      world: world,
      raw_token: raw_token,
      raw_token_2: raw_token_2,
      raw_token_other: raw_token_other
    }
  end

  describe "GET /api/stories/:story_id/characters" do
    test "200 — returns id and name for each character in the story", %{
      conn: conn,
      story: story,
      char_1: char_1,
      char_2: char_2,
      raw_token: token
    } do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> get("/api/stories/#{story.id}/characters")

      body = json_response(conn, 200)
      assert is_list(body)
      ids = Enum.map(body, & &1["id"])
      assert char_1.id in ids
      assert char_2.id in ids
      Enum.each(body, fn c -> assert Map.has_key?(c, "name") end)
    end

    test "401 without token", %{conn: conn, story: story} do
      conn = get(conn, "/api/stories/#{story.id}/characters")
      assert json_response(conn, 401)
    end

    test "403 when token story does not match path story_id", %{
      conn: conn,
      story: story,
      raw_token_other: token_other
    } do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token_other}")
        |> get("/api/stories/#{story.id}/characters")

      assert json_response(conn, 403)
    end
  end

  describe "GET /api/stories/:story_id/characters/:char_id" do
    test "200 — returns name, view id, version number, and resolved content", %{
      conn: conn,
      story: story,
      char_1: char_1,
      raw_token: token
    } do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> get("/api/stories/#{story.id}/characters/#{char_1.id}")

      body = json_response(conn, 200)
      assert body["id"] == char_1.id
      assert body["name"] == "Akko"
      assert body["character_view_id"]
      assert body["version_number"] == 1
      assert body["content"] == "Akko is a witch in training."
    end

    test "200 content null — character exists with view but no CVV", %{
      conn: conn,
      story: story,
      char_2: char_2,
      raw_token: token
    } do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> get("/api/stories/#{story.id}/characters/#{char_2.id}")

      body = json_response(conn, 200)
      assert body["id"] == char_2.id
      assert body["name"] == "Lotte"
      assert body["character_view_id"]
      assert is_nil(body["version_number"])
      assert is_nil(body["content"])
    end

    test "404 when char_id belongs to a different story", %{
      conn: conn,
      story: story,
      other_char: other_char,
      raw_token: token
    } do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> get("/api/stories/#{story.id}/characters/#{other_char.id}")

      assert json_response(conn, 404)
    end

    test "401 without token", %{conn: conn, story: story, char_1: char_1} do
      conn = get(conn, "/api/stories/#{story.id}/characters/#{char_1.id}")
      assert json_response(conn, 401)
    end
  end

  describe "POST /api/stories/:story_id/characters/:char_id/pieces" do
    test "201 — cuts new CVV; subsequent GET reflects new content", %{
      conn: conn,
      story: story,
      char_1: char_1,
      raw_token: token
    } do
      new_content = "Akko is now a full-fledged witch."

      post_conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> post("/api/stories/#{story.id}/characters/#{char_1.id}/pieces", %{
          "content" => new_content
        })

      body = json_response(post_conn, 201)
      assert body["id"]
      assert body["version_number"] == 2
      assert body["unresolvable_segments"] == []

      get_conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> get("/api/stories/#{story.id}/characters/#{char_1.id}")

      get_body = json_response(get_conn, 200)
      assert get_body["content"] == new_content
      assert get_body["version_number"] == 2
    end

    test "400 — missing content", %{conn: conn, story: story, char_1: char_1, raw_token: token} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> post("/api/stories/#{story.id}/characters/#{char_1.id}/pieces", %{})

      assert json_response(conn, 400)["error"] =~ "content"
    end

    test "400 — empty content", %{conn: conn, story: story, char_1: char_1, raw_token: token} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> post("/api/stories/#{story.id}/characters/#{char_1.id}/pieces", %{"content" => ""})

      assert json_response(conn, 400)["error"] =~ "content"
    end

    test "404 when char_id belongs to a different story", %{
      conn: conn,
      story: story,
      other_char: other_char,
      raw_token: token
    } do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> post("/api/stories/#{story.id}/characters/#{other_char.id}/pieces", %{
          "content" => "Some content."
        })

      assert json_response(conn, 404)
    end

    test "401 without token", %{conn: conn, story: story, char_1: char_1} do
      conn =
        post(conn, "/api/stories/#{story.id}/characters/#{char_1.id}/pieces", %{
          "content" => "Some content."
        })

      assert json_response(conn, 401)
    end
  end

  describe "GET /api/stories/:story_id/world" do
    test "200 — returns world_id, view id, version number, and resolved content", %{
      conn: conn,
      story: story,
      world: world,
      raw_token: token
    } do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> get("/api/stories/#{story.id}/world")

      body = json_response(conn, 200)
      assert body["world_id"] == world.id
      assert body["world_view_id"]
      assert body["version_number"] == 1
      assert body["content"] == "The witch academy world."
    end

    test "200 content null — world exists with view but no WVV", %{
      conn: conn,
      story_2: story_2,
      raw_token_2: token_2
    } do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token_2}")
        |> get("/api/stories/#{story_2.id}/world")

      body = json_response(conn, 200)
      assert body["world_id"]
      assert body["world_view_id"]
      assert is_nil(body["version_number"])
      assert is_nil(body["content"])
    end

    test "404 when no world record for story", %{
      conn: conn,
      other_story: other_story,
      raw_token_other: token_other
    } do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token_other}")
        |> get("/api/stories/#{other_story.id}/world")

      assert json_response(conn, 404)
    end

    test "401 without token", %{conn: conn, story: story} do
      conn = get(conn, "/api/stories/#{story.id}/world")
      assert json_response(conn, 401)
    end

    test "403 when token story does not match path story_id", %{
      conn: conn,
      story: story,
      raw_token_other: token_other
    } do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token_other}")
        |> get("/api/stories/#{story.id}/world")

      assert json_response(conn, 403)
    end
  end

  describe "POST /api/stories/:story_id/world/pieces" do
    test "201 — cuts new WVV; subsequent GET reflects new content", %{
      conn: conn,
      story: story,
      raw_token: token
    } do
      new_content = "The witch academy world, expanded."

      post_conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> post("/api/stories/#{story.id}/world/pieces", %{"content" => new_content})

      body = json_response(post_conn, 201)
      assert body["id"]
      assert body["version_number"] == 2
      assert body["unresolvable_segments"] == []

      get_conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> get("/api/stories/#{story.id}/world")

      get_body = json_response(get_conn, 200)
      assert get_body["content"] == new_content
      assert get_body["version_number"] == 2
    end

    test "400 — missing content", %{conn: conn, story: story, raw_token: token} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> post("/api/stories/#{story.id}/world/pieces", %{})

      assert json_response(conn, 400)["error"] =~ "content"
    end

    test "400 — empty content", %{conn: conn, story: story, raw_token: token} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> post("/api/stories/#{story.id}/world/pieces", %{"content" => ""})

      assert json_response(conn, 400)["error"] =~ "content"
    end

    test "404 when no world record for story", %{
      conn: conn,
      other_story: other_story,
      raw_token_other: token_other
    } do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token_other}")
        |> post("/api/stories/#{other_story.id}/world/pieces", %{"content" => "Some content."})

      assert json_response(conn, 404)
    end

    test "401 without token", %{conn: conn, story: story} do
      conn = post(conn, "/api/stories/#{story.id}/world/pieces", %{"content" => "Some content."})
      assert json_response(conn, 401)
    end
  end
end
