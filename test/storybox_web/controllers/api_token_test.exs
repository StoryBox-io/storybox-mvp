defmodule StoryboxWeb.ApiTokenTest do
  use StoryboxWeb.ConnCase

  setup do
    {:ok, user} =
      Storybox.Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "token_test@example.com",
        password: "Password1!",
        password_confirmation: "Password1!"
      })
      |> Ash.create()

    {:ok, other_user} =
      Storybox.Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "other_token_test@example.com",
        password: "Password1!",
        password_confirmation: "Password1!"
      })
      |> Ash.create()

    {:ok, story} =
      Storybox.Stories.Story
      |> Ash.Changeset.for_create(:create, %{
        title: "Token Test Story",
        user_id: user.id
      })
      |> Ash.create()

    {:ok, other_story} =
      Storybox.Stories.Story
      |> Ash.Changeset.for_create(:create, %{
        title: "Other User Story",
        user_id: other_user.id
      })
      |> Ash.create()

    %{user: user, story: story, other_story: other_story}
  end

  describe "POST /api/auth/token" do
    test "returns a token for valid credentials and owned story", %{
      conn: conn,
      story: story
    } do
      conn =
        post(conn, "/api/auth/token", %{
          email: "token_test@example.com",
          password: "Password1!",
          story_id: story.id
        })

      assert %{"token" => token} = json_response(conn, 200)
      assert is_binary(token) and byte_size(token) > 0
    end

    test "returned token is accepted by authenticated endpoints", %{
      conn: conn,
      story: story
    } do
      %{"token" => token} =
        conn
        |> post("/api/auth/token", %{
          email: "token_test@example.com",
          password: "Password1!",
          story_id: story.id
        })
        |> json_response(200)

      ping_conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{token}")
        |> get("/api/stories/#{story.id}/ping")

      assert json_response(ping_conn, 200)["status"] == "ok"
    end

    test "returns 401 for wrong password", %{conn: conn, story: story} do
      conn =
        post(conn, "/api/auth/token", %{
          email: "token_test@example.com",
          password: "wrongpassword",
          story_id: story.id
        })

      assert json_response(conn, 401)["error"] == "invalid credentials"
    end

    test "returns 401 for unknown email", %{conn: conn, story: story} do
      conn =
        post(conn, "/api/auth/token", %{
          email: "nobody@example.com",
          password: "Password1!",
          story_id: story.id
        })

      assert json_response(conn, 401)["error"] == "invalid credentials"
    end

    test "returns 404 for a story owned by a different user", %{
      conn: conn,
      other_story: other_story
    } do
      conn =
        post(conn, "/api/auth/token", %{
          email: "token_test@example.com",
          password: "Password1!",
          story_id: other_story.id
        })

      assert json_response(conn, 404)["error"] == "story not found"
    end

    test "returns 404 for a story_id that does not exist", %{conn: conn} do
      conn =
        post(conn, "/api/auth/token", %{
          email: "token_test@example.com",
          password: "Password1!",
          story_id: Ecto.UUID.generate()
        })

      assert json_response(conn, 404)["error"] == "story not found"
    end

    test "returns 422 when story_id is missing", %{conn: conn} do
      conn =
        post(conn, "/api/auth/token", %{
          email: "token_test@example.com",
          password: "Password1!"
        })

      assert json_response(conn, 422)["error"] =~ "required"
    end

    test "returns 422 when email is missing", %{conn: conn, story: story} do
      conn =
        post(conn, "/api/auth/token", %{
          password: "Password1!",
          story_id: story.id
        })

      assert json_response(conn, 422)["error"] =~ "required"
    end

    test "returns 422 when password is missing", %{conn: conn, story: story} do
      conn =
        post(conn, "/api/auth/token", %{
          email: "token_test@example.com",
          story_id: story.id
        })

      assert json_response(conn, 422)["error"] =~ "required"
    end
  end
end
