defmodule StoryboxWeb.SequenceWeightsTest do
  use StoryboxWeb.ConnCase

  alias Storybox.Accounts.ApiToken

  # Setup creates:
  #
  #   user ──── story ──── sequence ──── sequence_piece (v1, weights %{})
  #          └── other_story
  #
  # raw_token is scoped to story.

  setup do
    {:ok, user} =
      Storybox.Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "sequence_weights_test@example.com",
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

    {:ok, sequence} =
      Storybox.Stories.Sequence
      |> Ash.Changeset.for_create(:create, %{story_id: story.id, name: "Seq 1", slug: "seq-1"})
      |> Ash.create(authorize?: false)

    {:ok, piece} =
      Storybox.Stories.SequencePiece
      |> Ash.Changeset.for_create(:create, %{
        story_id: story.id,
        sequence_id: sequence.id,
        content_uri: "seq/#{sequence.id}/1.fountain",
        version_number: 1,
        weights: %{}
      })
      |> Ash.create(authorize?: false)

    %{
      story: story,
      other_story: other_story,
      sequence: sequence,
      piece: piece,
      raw_token: raw_token,
      other_token: other_token
    }
  end

  describe "POST /api/stories/:story_id/sequences/:seq_id/weights" do
    test "returns 200 with updated weights", %{
      conn: conn,
      story: story,
      sequence: sequence,
      raw_token: raw_token
    } do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{raw_token}")
        |> post("/api/stories/#{story.id}/sequences/#{sequence.id}/weights", %{
          "weights" => %{"importance" => 0.9}
        })

      body = json_response(conn, 200)
      assert body["weights"] == %{"importance" => 0.9}
      assert body["id"]
      assert body["version_number"] == 1
    end

    test "read-back: DB record has updated weights", %{
      conn: conn,
      story: story,
      sequence: sequence,
      piece: piece,
      raw_token: raw_token
    } do
      conn
      |> put_req_header("authorization", "Bearer #{raw_token}")
      |> post("/api/stories/#{story.id}/sequences/#{sequence.id}/weights", %{
        "weights" => %{"score" => 42}
      })

      updated = Ash.get!(Storybox.Stories.SequencePiece, piece.id, authorize?: false)
      assert updated.weights == %{"score" => 42}
    end

    test "returns 404 for unknown seq_id", %{
      conn: conn,
      story: story,
      raw_token: raw_token
    } do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{raw_token}")
        |> post(
          "/api/stories/#{story.id}/sequences/00000000-0000-0000-0000-000000000000/weights",
          %{"weights" => %{}}
        )

      assert json_response(conn, 404)["error"] == "not found"
    end

    test "returns 400 when weights key is absent", %{
      conn: conn,
      story: story,
      sequence: sequence,
      raw_token: raw_token
    } do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{raw_token}")
        |> post("/api/stories/#{story.id}/sequences/#{sequence.id}/weights", %{})

      assert json_response(conn, 400)["error"] == "weights is required"
    end

    test "returns 401 without Authorization header", %{
      conn: conn,
      story: story,
      sequence: sequence
    } do
      conn =
        conn
        |> post("/api/stories/#{story.id}/sequences/#{sequence.id}/weights", %{
          "weights" => %{}
        })

      assert json_response(conn, 401)
    end

    test "returns 403 when token is scoped to a different story", %{
      conn: conn,
      story: story,
      sequence: sequence,
      other_token: other_token
    } do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{other_token}")
        |> post("/api/stories/#{story.id}/sequences/#{sequence.id}/weights", %{
          "weights" => %{}
        })

      assert json_response(conn, 403)
    end
  end
end
