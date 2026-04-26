defmodule StoryboxWeb.SynopsisViewTest do
  use StoryboxWeb.ConnCase

  alias Storybox.Accounts.ApiToken

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

  describe "GET /api/stories/:story_id/views/synopsis" do
    test "returns 404 when no synopsis versions exist", %{
      conn: conn,
      story: story,
      raw_token: raw_token
    } do
      conn =
        conn
        |> authed(raw_token)
        |> get("/api/stories/#{story.id}/views/synopsis")

      assert json_response(conn, 404)["error"] == "no synopsis found"
    end

    test "returns latest version with content when versions exist", %{
      conn: conn,
      story: story,
      raw_token: raw_token
    } do
      {:ok, _v1} =
        Storybox.Stories.SynopsisView
        |> Ash.ActionInput.for_action(:create_version, %{
          story_id: story.id,
          content: "First synopsis draft."
        })
        |> Ash.run_action()

      {:ok, _v2} =
        Storybox.Stories.SynopsisView
        |> Ash.ActionInput.for_action(:create_version, %{
          story_id: story.id,
          content: "Second synopsis draft."
        })
        |> Ash.run_action()

      conn =
        conn
        |> authed(raw_token)
        |> get("/api/stories/#{story.id}/views/synopsis")

      assert %{
               "story_id" => story_id,
               "version_number" => version_number,
               "inserted_at" => _inserted_at,
               "content" => content
             } = json_response(conn, 200)

      assert story_id == story.id
      assert version_number == 2
      assert content == "Second synopsis draft."
    end

    test "returns 503 when content_uri points to a nonexistent MinIO object", %{
      conn: conn,
      story: story,
      raw_token: raw_token
    } do
      {:ok, _version} =
        Storybox.Stories.SynopsisView
        |> Ash.Changeset.for_create(:create, %{
          story_id: story.id,
          content_uri: "storybox://stories/#{story.id}/synopsis/v999_nonexistent.fountain",
          version_number: 1
        })
        |> Ash.create()

      conn =
        conn
        |> authed(raw_token)
        |> get("/api/stories/#{story.id}/views/synopsis")

      assert json_response(conn, 503)["error"] == "content unavailable"
    end

    test "returns non-ASCII characters (em dash, smart quotes) without double-encoding", %{
      conn: conn,
      story: story,
      raw_token: raw_token
    } do
      content = "Frank carries something back \u2014 something that has no name."

      {:ok, _v} =
        Storybox.Stories.SynopsisView
        |> Ash.ActionInput.for_action(:create_version, %{
          story_id: story.id,
          content: content
        })
        |> Ash.run_action()

      conn =
        conn
        |> authed(raw_token)
        |> get("/api/stories/#{story.id}/views/synopsis")

      body = json_response(conn, 200)

      assert body["content"] == content,
             "content was double-encoded: #{inspect(body["content"])}"
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
