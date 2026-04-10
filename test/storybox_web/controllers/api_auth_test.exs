defmodule StoryboxWeb.ApiAuthTest do
  use StoryboxWeb.ConnCase

  alias Storybox.Accounts.ApiToken

  setup do
    {:ok, user} =
      Storybox.Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "api_auth_test@example.com",
        password: "password123!",
        password_confirmation: "password123!"
      })
      |> Ash.create()

    {:ok, story} =
      Storybox.Stories.Story
      |> Ash.Changeset.for_create(:create, %{title: "Auth Test Story", user_id: user.id})
      |> Ash.create()

    {:ok, other_story} =
      Storybox.Stories.Story
      |> Ash.Changeset.for_create(:create, %{title: "Other Story", user_id: user.id})
      |> Ash.create()

    {:ok, raw_token, _} = ApiToken.generate(%{story_id: story.id, user_id: user.id})

    %{user: user, story: story, other_story: other_story, raw_token: raw_token}
  end

  describe "GET /api/stories/:story_id/ping" do
    test "returns 401 with no Authorization header", %{conn: conn, story: story} do
      conn = get(conn, "/api/stories/#{story.id}/ping")
      assert json_response(conn, 401)["error"] == "unauthorized"
    end

    test "returns 401 with an invalid token", %{conn: conn, story: story} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer notavalidtoken")
        |> get("/api/stories/#{story.id}/ping")

      assert json_response(conn, 401)["error"] == "unauthorized"
    end

    test "returns 401 with a non-bearer Authorization header", %{conn: conn, story: story} do
      conn =
        conn
        |> put_req_header("authorization", "Basic dXNlcjpwYXNz")
        |> get("/api/stories/#{story.id}/ping")

      assert json_response(conn, 401)["error"] == "unauthorized"
    end

    test "returns 403 when token is scoped to a different story", %{
      conn: conn,
      other_story: other_story,
      raw_token: raw_token
    } do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{raw_token}")
        |> get("/api/stories/#{other_story.id}/ping")

      assert json_response(conn, 403)["error"] == "forbidden"
    end

    test "returns 200 with a valid token and matching story_id", %{
      conn: conn,
      story: story,
      raw_token: raw_token
    } do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{raw_token}")
        |> get("/api/stories/#{story.id}/ping")

      assert %{"status" => "ok", "story_id" => story_id} = json_response(conn, 200)
      assert story_id == story.id
    end

    test "returns 401 for an expired token", %{conn: conn, story: story, user: user} do
      past = DateTime.add(DateTime.utc_now(), -3600, :second)

      {:ok, expired_token, _} =
        ApiToken.generate(%{story_id: story.id, user_id: user.id, expires_at: past})

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{expired_token}")
        |> get("/api/stories/#{story.id}/ping")

      assert json_response(conn, 401)["error"] == "unauthorized"
    end
  end
end
