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
    test "returns 404 when no SynopsisView exists for the story", %{
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

    test "returns 404 when SynopsisView exists but has no versions", %{
      conn: conn,
      story: story,
      raw_token: raw_token
    } do
      {:ok, _sv} =
        Storybox.Stories.SynopsisView
        |> Ash.ActionInput.for_action(:ensure_for_story, %{story_id: story.id})
        |> Ash.run_action()

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

      {:ok, _vv1} =
        Storybox.Stories.SynopsisViewVersion
        |> Ash.Changeset.for_create(:create, %{synopsis_view_id: sv.id, version_number: 1})
        |> Ash.create()

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
end
