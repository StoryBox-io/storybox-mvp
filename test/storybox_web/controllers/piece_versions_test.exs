defmodule StoryboxWeb.PieceVersionsTest do
  use StoryboxWeb.ConnCase

  alias Storybox.Accounts.ApiToken

  # Shared setup creates:
  #
  #   user ──── story ──── scene_1 ──── sv_1 ── sp_v1 (v1, existing)
  #          └── other_story ──── other_scene ──── other_sv
  #
  # raw_token is scoped to story.

  setup do
    {:ok, user} =
      Storybox.Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "piece_versions_test@example.com",
        password: "password123!",
        password_confirmation: "password123!"
      })
      |> Ash.create()

    {:ok, story} =
      Storybox.Stories.Story
      |> Ash.Changeset.for_create(:create, %{title: "Piece Versions Story", user_id: user.id})
      |> Ash.create()

    {:ok, other_story} =
      Storybox.Stories.Story
      |> Ash.Changeset.for_create(:create, %{title: "Other Story", user_id: user.id})
      |> Ash.create()

    {:ok, raw_token, _} = ApiToken.generate(%{story_id: story.id, user_id: user.id})

    {:ok, scene_1} =
      Storybox.Stories.Scene
      |> Ash.Changeset.for_create(:create, %{title: "Scene", story_id: story.id})
      |> Ash.create(authorize?: false)

    {:ok, sv_1} =
      Storybox.Stories.ScriptView
      |> Ash.Changeset.for_create(:create, %{title: "Scene", scene_id: scene_1.id})
      |> Ash.create(authorize?: false)

    {:ok, _sp_v1} =
      Storybox.Stories.ScriptPiece
      |> Ash.Changeset.for_create(:create, %{
        script_view_id: sv_1.id,
        content_uri: "storybox://test/scene/v1.fountain",
        version_number: 1,
        upstream_status: :current,
        weights: %{}
      })
      |> Ash.create(authorize?: false)

    {:ok, other_scene} =
      Storybox.Stories.Scene
      |> Ash.Changeset.for_create(:create, %{title: "Other Scene", story_id: other_story.id})
      |> Ash.create(authorize?: false)

    {:ok, other_sv} =
      Storybox.Stories.ScriptView
      |> Ash.Changeset.for_create(:create, %{title: "Other Scene", scene_id: other_scene.id})
      |> Ash.create(authorize?: false)

    %{
      story: story,
      sv_1: sv_1,
      other_sv: other_sv,
      raw_token: raw_token
    }
  end

  describe "POST /api/stories/:story_id/scenes/:id/versions" do
    test "creates a new scene version and returns 201", %{
      conn: conn,
      story: story,
      sv_1: sv_1,
      raw_token: raw_token
    } do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{raw_token}")
        |> post("/api/stories/#{story.id}/scenes/#{sv_1.id}/versions", %{
          "content" => "INT. OFFICE - NIGHT\nThey argue."
        })

      body = json_response(conn, 201)
      assert body["version_number"]
      assert body["upstream_status"] == "current"
      assert body["weights"] == %{}
      assert body["id"]
    end

    test "returns version_number 2 when a prior version already exists", %{
      conn: conn,
      story: story,
      sv_1: sv_1,
      raw_token: raw_token
    } do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{raw_token}")
        |> post("/api/stories/#{story.id}/scenes/#{sv_1.id}/versions", %{
          "content" => "INT. OFFICE - NIGHT\nNew content."
        })

      assert json_response(conn, 201)["version_number"] == 2
    end

    test "returns 400 when content is missing", %{
      conn: conn,
      story: story,
      sv_1: sv_1,
      raw_token: raw_token
    } do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{raw_token}")
        |> post("/api/stories/#{story.id}/scenes/#{sv_1.id}/versions", %{})

      assert json_response(conn, 400)["error"] == "content is required"
    end

    test "returns 404 when scene belongs to a different story", %{
      conn: conn,
      story: story,
      other_sv: other_sv,
      raw_token: raw_token
    } do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{raw_token}")
        |> post("/api/stories/#{story.id}/scenes/#{other_sv.id}/versions", %{
          "content" => "Some content."
        })

      assert json_response(conn, 404)["error"] == "not found"
    end

    test "returns 404 for a non-existent scene id", %{
      conn: conn,
      story: story,
      raw_token: raw_token
    } do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{raw_token}")
        |> post(
          "/api/stories/#{story.id}/scenes/00000000-0000-0000-0000-000000000000/versions",
          %{
            "content" => "Some content."
          }
        )

      assert json_response(conn, 404)["error"] == "not found"
    end
  end
end
