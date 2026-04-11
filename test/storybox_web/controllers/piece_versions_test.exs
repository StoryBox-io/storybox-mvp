defmodule StoryboxWeb.PieceVersionsTest do
  use StoryboxWeb.ConnCase

  alias Storybox.Accounts.ApiToken

  # Shared setup creates:
  #
  #   user ──── story ──── seq_1 ──── seq_v1 (v1, existing)
  #          │              └───── scene_1 ── scene_v1 (v1, existing)
  #          └── other_story ── other_seq ── other_scene
  #
  # raw_token is scoped to story. other_seq/other_scene are used for cross-story 404 tests.

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

    {:ok, seq_1} =
      Storybox.Stories.SequencePiece
      |> Ash.Changeset.for_create(:create, %{
        title: "Seq",
        act: "Act I",
        position: 1,
        story_id: story.id
      })
      |> Ash.create(authorize?: false)

    {:ok, scene_1} =
      Storybox.Stories.ScenePiece
      |> Ash.Changeset.for_create(:create, %{
        title: "Scene",
        position: 1,
        sequence_piece_id: seq_1.id
      })
      |> Ash.create(authorize?: false)

    # Existing v1 records created directly (bypasses MinIO in setup)
    {:ok, _seq_v1} =
      Storybox.Stories.SequenceVersion
      |> Ash.Changeset.for_create(:create, %{
        sequence_piece_id: seq_1.id,
        content_uri: "storybox://test/seq/v1.fountain",
        version_number: 1,
        upstream_status: :current,
        weights: %{}
      })
      |> Ash.create(authorize?: false)

    {:ok, _scene_v1} =
      Storybox.Stories.SceneVersion
      |> Ash.Changeset.for_create(:create, %{
        scene_piece_id: scene_1.id,
        content_uri: "storybox://test/scene/v1.fountain",
        version_number: 1,
        upstream_status: :current,
        weights: %{}
      })
      |> Ash.create(authorize?: false)

    {:ok, other_seq} =
      Storybox.Stories.SequencePiece
      |> Ash.Changeset.for_create(:create, %{
        title: "Other Seq",
        position: 1,
        story_id: other_story.id
      })
      |> Ash.create(authorize?: false)

    {:ok, other_scene} =
      Storybox.Stories.ScenePiece
      |> Ash.Changeset.for_create(:create, %{
        title: "Other Scene",
        position: 1,
        sequence_piece_id: other_seq.id
      })
      |> Ash.create(authorize?: false)

    %{
      story: story,
      seq_1: seq_1,
      scene_1: scene_1,
      other_seq: other_seq,
      other_scene: other_scene,
      raw_token: raw_token
    }
  end

  describe "POST /api/stories/:story_id/sequences/:id/versions" do
    test "creates a new version and returns 201", %{
      conn: conn,
      story: story,
      seq_1: seq_1,
      raw_token: raw_token
    } do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{raw_token}")
        |> post("/api/stories/#{story.id}/sequences/#{seq_1.id}/versions", %{
          "content" => "EXT. PARK - DAY\nSomething happens."
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
      seq_1: seq_1,
      raw_token: raw_token
    } do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{raw_token}")
        |> post("/api/stories/#{story.id}/sequences/#{seq_1.id}/versions", %{
          "content" => "EXT. PARK - DAY\nNew content."
        })

      assert json_response(conn, 201)["version_number"] == 2
    end

    test "returns 400 when content is missing", %{
      conn: conn,
      story: story,
      seq_1: seq_1,
      raw_token: raw_token
    } do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{raw_token}")
        |> post("/api/stories/#{story.id}/sequences/#{seq_1.id}/versions", %{})

      assert json_response(conn, 400)["error"] == "content is required"
    end

    test "returns 400 when content is empty string", %{
      conn: conn,
      story: story,
      seq_1: seq_1,
      raw_token: raw_token
    } do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{raw_token}")
        |> post("/api/stories/#{story.id}/sequences/#{seq_1.id}/versions", %{"content" => ""})

      assert json_response(conn, 400)["error"] == "content is required"
    end

    test "returns 404 when sequence belongs to a different story", %{
      conn: conn,
      story: story,
      other_seq: other_seq,
      raw_token: raw_token
    } do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{raw_token}")
        |> post("/api/stories/#{story.id}/sequences/#{other_seq.id}/versions", %{
          "content" => "Some content."
        })

      assert json_response(conn, 404)["error"] == "not found"
    end

    test "returns 404 for a non-existent sequence id", %{
      conn: conn,
      story: story,
      raw_token: raw_token
    } do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{raw_token}")
        |> post(
          "/api/stories/#{story.id}/sequences/00000000-0000-0000-0000-000000000000/versions",
          %{
            "content" => "Some content."
          }
        )

      assert json_response(conn, 404)["error"] == "not found"
    end
  end

  describe "POST /api/stories/:story_id/scenes/:id/versions" do
    test "creates a new scene version and returns 201", %{
      conn: conn,
      story: story,
      scene_1: scene_1,
      raw_token: raw_token
    } do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{raw_token}")
        |> post("/api/stories/#{story.id}/scenes/#{scene_1.id}/versions", %{
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
      scene_1: scene_1,
      raw_token: raw_token
    } do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{raw_token}")
        |> post("/api/stories/#{story.id}/scenes/#{scene_1.id}/versions", %{
          "content" => "INT. OFFICE - NIGHT\nNew content."
        })

      assert json_response(conn, 201)["version_number"] == 2
    end

    test "returns 400 when content is missing", %{
      conn: conn,
      story: story,
      scene_1: scene_1,
      raw_token: raw_token
    } do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{raw_token}")
        |> post("/api/stories/#{story.id}/scenes/#{scene_1.id}/versions", %{})

      assert json_response(conn, 400)["error"] == "content is required"
    end

    test "returns 404 when scene's parent sequence belongs to a different story", %{
      conn: conn,
      story: story,
      other_scene: other_scene,
      raw_token: raw_token
    } do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{raw_token}")
        |> post("/api/stories/#{story.id}/scenes/#{other_scene.id}/versions", %{
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
