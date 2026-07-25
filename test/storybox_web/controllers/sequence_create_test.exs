defmodule StoryboxWeb.SequenceCreateTest do
  use StoryboxWeb.ConnCase

  require Ash.Query

  alias Storybox.Accounts.ApiToken

  # Shared setup creates:
  #
  #   user ──── story        (scoped by raw_token)
  #          └── other_story  (scoped by raw_token_other)
  #
  # Both stories bootstrap an empty StorySpine; no Sequences exist yet.

  setup do
    {:ok, user} =
      Storybox.Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "sequence_create_test@example.com",
        password: "password123!",
        password_confirmation: "password123!"
      })
      |> Ash.create()

    {:ok, story} =
      Storybox.Stories.Story
      |> Ash.Changeset.for_create(:create, %{title: "Create Sequence Story", user_id: user.id})
      |> Ash.create()

    {:ok, other_story} =
      Storybox.Stories.Story
      |> Ash.Changeset.for_create(:create, %{title: "Other Story", user_id: user.id})
      |> Ash.create()

    {:ok, raw_token, _} = ApiToken.generate(%{story_id: story.id, user_id: user.id})
    {:ok, raw_token_other, _} = ApiToken.generate(%{story_id: other_story.id, user_id: user.id})

    %{
      story: story,
      other_story: other_story,
      raw_token: raw_token,
      raw_token_other: raw_token_other
    }
  end

  defp auth(conn, token), do: put_req_header(conn, "authorization", "Bearer #{token}")

  defp spine_entry_count(story_id) do
    spine =
      Storybox.Stories.StorySpine
      |> Ash.Query.filter(story_id == ^story_id)
      |> Ash.read_one!(authorize?: false)

    Storybox.Stories.StorySpineEntry
    |> Ash.Query.filter(story_spine_id == ^spine.id)
    |> Ash.count!(authorize?: false)
  end

  describe "POST /api/stories/:story_id/sequences" do
    test "201 with {id, slug, name} and the sequence lands OFF the spine", %{
      conn: conn,
      story: story,
      raw_token: raw_token
    } do
      conn =
        conn
        |> auth(raw_token)
        |> post("/api/stories/#{story.id}/sequences", %{"name" => "Act One", "slug" => "act-1"})

      body = json_response(conn, 201)
      assert body["id"]
      assert body["slug"] == "act-1"
      assert body["name"] == "Act One"

      sequence =
        Storybox.Stories.Sequence
        |> Ash.Query.filter(story_id == ^story.id and slug == "act-1")
        |> Ash.read_one!(authorize?: false)

      assert sequence.id == body["id"]
      # Off-spine: no StorySpineEntry was created for it.
      assert spine_entry_count(story.id) == 0
    end

    test "409 when the slug already exists for the story", %{
      conn: conn,
      story: story,
      raw_token: raw_token
    } do
      build_conn()
      |> auth(raw_token)
      |> post("/api/stories/#{story.id}/sequences", %{"name" => "Act One", "slug" => "act-1"})

      conn =
        conn
        |> auth(raw_token)
        |> post("/api/stories/#{story.id}/sequences", %{"name" => "Duplicate", "slug" => "act-1"})

      assert json_response(conn, 409)["error"] == "sequence slug already exists"
    end

    test "the same slug in a different story still succeeds", %{
      conn: conn,
      story: story,
      other_story: other_story,
      raw_token: raw_token,
      raw_token_other: raw_token_other
    } do
      build_conn()
      |> auth(raw_token)
      |> post("/api/stories/#{story.id}/sequences", %{"name" => "Act One", "slug" => "act-1"})

      conn =
        conn
        |> auth(raw_token_other)
        |> post("/api/stories/#{other_story.id}/sequences", %{
          "name" => "Act One",
          "slug" => "act-1"
        })

      assert json_response(conn, 201)["slug"] == "act-1"
    end

    test "400 when name is missing", %{conn: conn, story: story, raw_token: raw_token} do
      conn =
        conn
        |> auth(raw_token)
        |> post("/api/stories/#{story.id}/sequences", %{"slug" => "act-1"})

      assert json_response(conn, 400)["error"] == "name is required"
    end

    test "400 when slug is missing", %{conn: conn, story: story, raw_token: raw_token} do
      conn =
        conn
        |> auth(raw_token)
        |> post("/api/stories/#{story.id}/sequences", %{"name" => "Act One"})

      assert json_response(conn, 400)["error"] == "slug is required"
    end
  end

  describe "create → insert → cut round trip" do
    test "a just-created off-spine sequence is placed by spine_insert with no 409, then cut", %{
      conn: conn,
      story: story,
      raw_token: raw_token
    } do
      # 1. Create the sequence OFF the spine.
      created =
        build_conn()
        |> auth(raw_token)
        |> post("/api/stories/#{story.id}/sequences", %{"name" => "Act One", "slug" => "act-1"})
        |> json_response(201)

      seq_id = created["id"]
      assert spine_entry_count(story.id) == 0

      # 2. Insert it at an explicit position on the FIRST call — no 409.
      insert_body =
        build_conn()
        |> auth(raw_token)
        |> post("/api/stories/#{story.id}/sequences/#{seq_id}/spine/insert", %{"position" => 1})
        |> json_response(201)

      assert insert_body["sequence_id"] == seq_id
      assert insert_body["position"] == 1
      assert spine_entry_count(story.id) == 1

      # 3. Cut the synopsis view — the placed sequence appears in the cut. It has
      # no SynopsisPiece, so it surfaces as a single unresolvable segment.
      cut_body =
        conn
        |> auth(raw_token)
        |> post("/api/stories/#{story.id}/views/synopsis/cut")
        |> json_response(201)

      assert cut_body["version_number"] >= 1
      assert length(cut_body["unresolvable_segments"]) == 1
      [seg] = cut_body["unresolvable_segments"]
      assert seg["position"] == 1
    end
  end
end
