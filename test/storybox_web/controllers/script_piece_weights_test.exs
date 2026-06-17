defmodule StoryboxWeb.ScriptPieceWeightsTest do
  use StoryboxWeb.ConnCase

  alias Storybox.Accounts.ApiToken

  # Setup creates:
  #
  #   user ──── story ──── scene ──── script_piece (v1, weights %{})
  #          └── other_story
  #
  # raw_token is scoped to story.

  setup do
    {:ok, user} =
      Storybox.Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "script_piece_weights_test@example.com",
        password: "password123!",
        password_confirmation: "password123!"
      })
      |> Ash.create()

    {:ok, story} =
      Storybox.Stories.Story
      |> Ash.Changeset.for_create(:create, %{title: "Weights Story", user_id: user.id})
      |> Ash.create()

    {:ok, other_story} =
      Storybox.Stories.Story
      |> Ash.Changeset.for_create(:create, %{title: "Other Story", user_id: user.id})
      |> Ash.create()

    {:ok, raw_token, _} = ApiToken.generate(%{story_id: story.id, user_id: user.id})
    {:ok, other_token, _} = ApiToken.generate(%{story_id: other_story.id, user_id: user.id})

    {:ok, scene} =
      Storybox.Stories.Scene
      |> Ash.Changeset.for_create(:create, %{story_id: story.id, slug: "scene-1"})
      |> Ash.create(authorize?: false)

    {:ok, piece} =
      Storybox.Stories.ScriptPiece
      |> Ash.ActionInput.for_action(:create_version, %{
        scene_id: scene.id,
        content: "INT. OFFICE - DAY"
      })
      |> Ash.run_action(authorize?: false)

    %{
      story: story,
      other_story: other_story,
      scene: scene,
      piece: piece,
      raw_token: raw_token,
      other_token: other_token
    }
  end

  describe "POST /api/stories/:story_id/scenes/:scene_id/weights" do
    test "returns 200 with updated weights", %{
      conn: conn,
      story: story,
      scene: scene,
      raw_token: raw_token
    } do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{raw_token}")
        |> post("/api/stories/#{story.id}/scenes/#{scene.id}/weights", %{
          "weights" => %{"importance" => 0.8}
        })

      body = json_response(conn, 200)
      assert body["weights"] == %{"importance" => 0.8}
      assert body["id"]
      assert body["version_number"] == 1
    end

    test "read-back: DB record has updated weights", %{
      conn: conn,
      story: story,
      scene: scene,
      piece: piece,
      raw_token: raw_token
    } do
      conn
      |> put_req_header("authorization", "Bearer #{raw_token}")
      |> post("/api/stories/#{story.id}/scenes/#{scene.id}/weights", %{
        "weights" => %{"score" => 99}
      })

      updated = Ash.get!(Storybox.Stories.ScriptPiece, piece.id, authorize?: false)
      assert updated.weights == %{"score" => 99}
    end

    test "full-map replace: prior keys are dropped", %{
      conn: conn,
      story: story,
      scene: scene,
      piece: piece,
      raw_token: raw_token
    } do
      conn
      |> put_req_header("authorization", "Bearer #{raw_token}")
      |> post("/api/stories/#{story.id}/scenes/#{scene.id}/weights", %{
        "weights" => %{"a" => 1}
      })

      conn
      |> put_req_header("authorization", "Bearer #{raw_token}")
      |> post("/api/stories/#{story.id}/scenes/#{scene.id}/weights", %{
        "weights" => %{"b" => 2}
      })

      updated = Ash.get!(Storybox.Stories.ScriptPiece, piece.id, authorize?: false)
      assert updated.weights == %{"b" => 2}
      refute Map.has_key?(updated.weights, "a")
    end

    test "returns 400 when weights key is absent", %{
      conn: conn,
      story: story,
      scene: scene,
      raw_token: raw_token
    } do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{raw_token}")
        |> post("/api/stories/#{story.id}/scenes/#{scene.id}/weights", %{})

      assert json_response(conn, 400)["error"] == "weights is required"
    end

    test "returns 400 when weights value is not a map", %{
      conn: conn,
      story: story,
      scene: scene,
      raw_token: raw_token
    } do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{raw_token}")
        |> post("/api/stories/#{story.id}/scenes/#{scene.id}/weights", %{
          "weights" => "not_a_map"
        })

      assert json_response(conn, 400)["error"] == "weights is required"
    end

    test "returns 404 for unknown scene_id", %{
      conn: conn,
      story: story,
      raw_token: raw_token
    } do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{raw_token}")
        |> post(
          "/api/stories/#{story.id}/scenes/00000000-0000-0000-0000-000000000000/weights",
          %{"weights" => %{}}
        )

      assert json_response(conn, 404)["error"] == "not found"
    end

    test "returns 404 when scene belongs to a different story", %{
      conn: conn,
      story: story,
      raw_token: raw_token,
      other_story: other_story
    } do
      {:ok, other_scene} =
        Storybox.Stories.Scene
        |> Ash.Changeset.for_create(:create, %{story_id: other_story.id, slug: "other-scene"})
        |> Ash.create(authorize?: false)

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{raw_token}")
        |> post("/api/stories/#{story.id}/scenes/#{other_scene.id}/weights", %{
          "weights" => %{}
        })

      assert json_response(conn, 404)["error"] == "not found"
    end

    test "returns 404 when scene has no ScriptPiece", %{
      conn: conn,
      story: story,
      raw_token: raw_token
    } do
      {:ok, empty_scene} =
        Storybox.Stories.Scene
        |> Ash.Changeset.for_create(:create, %{story_id: story.id, slug: "empty-scene"})
        |> Ash.create(authorize?: false)

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{raw_token}")
        |> post("/api/stories/#{story.id}/scenes/#{empty_scene.id}/weights", %{
          "weights" => %{}
        })

      assert json_response(conn, 404)["error"] == "not found"
    end

    test "returns 401 without Authorization header", %{
      conn: conn,
      story: story,
      scene: scene
    } do
      conn =
        conn
        |> post("/api/stories/#{story.id}/scenes/#{scene.id}/weights", %{
          "weights" => %{}
        })

      assert json_response(conn, 401)
    end

    test "returns 403 when token is scoped to a different story", %{
      conn: conn,
      story: story,
      scene: scene,
      other_token: other_token
    } do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{other_token}")
        |> post("/api/stories/#{story.id}/scenes/#{scene.id}/weights", %{
          "weights" => %{}
        })

      assert json_response(conn, 403)
    end
  end
end
