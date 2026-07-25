defmodule StoryboxWeb.SynopsisPieceTest do
  use StoryboxWeb.ConnCase

  require Ash.Query

  alias Storybox.Accounts.ApiToken

  # Shared setup creates:
  #
  #   user ──── story ──── existing_seq (slug "act-1", with synopsis_v1)
  #
  # raw_token is scoped to story.

  setup do
    {:ok, user} =
      Storybox.Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "synopsis_piece_test@example.com",
        password: "password123!",
        password_confirmation: "password123!"
      })
      |> Ash.create()

    {:ok, story} =
      Storybox.Stories.Story
      |> Ash.Changeset.for_create(:create, %{title: "Synopsis Piece Story", user_id: user.id})
      |> Ash.create()

    {:ok, raw_token, _} = ApiToken.generate(%{story_id: story.id, user_id: user.id})

    {:ok, existing_seq} =
      Storybox.Stories.Sequence
      |> Ash.Changeset.for_create(:create, %{
        story_id: story.id,
        name: "Act One",
        slug: "act-1"
      })
      |> Ash.create(authorize?: false)

    {:ok, _synopsis_v1} =
      Storybox.Stories.SynopsisPiece
      |> Ash.ActionInput.for_action(:create_version, %{
        story_id: story.id,
        sequence_id: existing_seq.id,
        content: "Opening synopsis prose."
      })
      |> Ash.run_action(authorize?: false)

    %{story: story, existing_seq: existing_seq, raw_token: raw_token}
  end

  describe "POST /api/stories/:story_id/sequences/:seq_slug/synopsis/pieces" do
    test "creates a new version on an existing sequence and returns 201", %{
      conn: conn,
      story: story,
      raw_token: raw_token
    } do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{raw_token}")
        |> post("/api/stories/#{story.id}/sequences/act-1/synopsis/pieces", %{
          "content" => "Revised synopsis prose."
        })

      body = json_response(conn, 201)
      assert body["version_number"] == 2
      assert body["id"]
      assert body["inserted_at"]
      refute Map.has_key?(body, "weights")
      refute Map.has_key?(body, "sequence_id")
    end

    test "returns 404 for an unknown slug and creates no sequence or spine entry", %{
      conn: conn,
      story: story,
      raw_token: raw_token
    } do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{raw_token}")
        |> post("/api/stories/#{story.id}/sequences/act-2/synopsis/pieces", %{
          "content" => "Brand new sequence synopsis."
        })

      assert json_response(conn, 404)["error"] == "sequence not found"

      sequence =
        Storybox.Stories.Sequence
        |> Ash.Query.filter(story_id == ^story.id and slug == "act-2")
        |> Ash.read_one!(authorize?: false)

      refute sequence

      # The story bootstraps an (empty) spine; the failed write adds no entry.
      spine =
        Storybox.Stories.StorySpine
        |> Ash.Query.filter(story_id == ^story.id)
        |> Ash.read_one!(authorize?: false)

      entry_count =
        Storybox.Stories.StorySpineEntry
        |> Ash.Query.filter(story_spine_id == ^spine.id)
        |> Ash.count!(authorize?: false)

      assert entry_count == 0
    end

    test "returns 400 when content is missing", %{
      conn: conn,
      story: story,
      raw_token: raw_token
    } do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{raw_token}")
        |> post("/api/stories/#{story.id}/sequences/act-1/synopsis/pieces", %{})

      assert json_response(conn, 400)["error"] == "content is required"
    end

    test "returns 400 when content is empty", %{
      conn: conn,
      story: story,
      raw_token: raw_token
    } do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{raw_token}")
        |> post("/api/stories/#{story.id}/sequences/act-1/synopsis/pieces", %{
          "content" => ""
        })

      assert json_response(conn, 400)["error"] == "content is required"
    end
  end
end
