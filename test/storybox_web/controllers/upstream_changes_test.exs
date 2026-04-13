defmodule StoryboxWeb.UpstreamChangesTest do
  use StoryboxWeb.ConnCase

  alias Storybox.Accounts.ApiToken

  # Shared setup creates:
  #
  #   user ──── story ──── seq_1 ──── seq_v1 ──► UC1 (acknowledged: false, component_type: :character)
  #                         └─── scene_1 ── scene_v1 ──► UC2 (acknowledged: true,  component_type: :world)
  #          └── other_story ──── other_seq ──── other_seq_v1 ──► other_UC (acknowledged: false)
  #
  # raw_token is scoped to story.
  # UC1 must appear in responses; UC2 must not (acknowledged). other_UC must not (wrong story).

  setup do
    {:ok, user} =
      Storybox.Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "upstream_changes_test@example.com",
        password: "password123!",
        password_confirmation: "password123!"
      })
      |> Ash.create()

    {:ok, story} =
      Storybox.Stories.Story
      |> Ash.Changeset.for_create(:create, %{title: "Upstream Test Story", user_id: user.id})
      |> Ash.create()

    {:ok, other_story} =
      Storybox.Stories.Story
      |> Ash.Changeset.for_create(:create, %{title: "Other Story", user_id: user.id})
      |> Ash.create()

    {:ok, raw_token, _} = ApiToken.generate(%{story_id: story.id, user_id: user.id})

    {:ok, seq_1} =
      Storybox.Stories.SequencePiece
      |> Ash.Changeset.for_create(:create, %{
        title: "Act I Seq",
        act: "Act I",
        position: 1,
        story_id: story.id
      })
      |> Ash.create(authorize?: false)

    {:ok, seq_v1} =
      Storybox.Stories.SequenceVersion
      |> Ash.Changeset.for_create(:create, %{
        sequence_piece_id: seq_1.id,
        content_uri: "storybox://test/seq/v1.fountain",
        version_number: 1,
        upstream_status: :stale,
        weights: %{}
      })
      |> Ash.create(authorize?: false)

    {:ok, scene_1} =
      Storybox.Stories.ScenePiece
      |> Ash.Changeset.for_create(:create, %{
        title: "Scene 1",
        position: 1,
        sequence_piece_id: seq_1.id
      })
      |> Ash.create(authorize?: false)

    {:ok, scene_v1} =
      Storybox.Stories.SceneVersion
      |> Ash.Changeset.for_create(:create, %{
        scene_piece_id: scene_1.id,
        content_uri: "storybox://test/scene/v1.fountain",
        version_number: 1,
        upstream_status: :stale,
        weights: %{}
      })
      |> Ash.create(authorize?: false)

    # UC1 — unacknowledged, on seq_v1 (should appear in responses)
    {:ok, uc1} =
      Storybox.Stories.UpstreamChange
      |> Ash.Changeset.for_create(:create, %{
        piece_version_type: :sequence_version,
        piece_version_id: seq_v1.id,
        component_type: :character,
        component_id: story.id,
        version_before: "v1",
        version_after: "v2"
      })
      |> Ash.create(authorize?: false)

    # UC2 — acknowledged, on scene_v1 (must NOT appear in responses)
    {:ok, uc2} =
      Storybox.Stories.UpstreamChange
      |> Ash.Changeset.for_create(:create, %{
        piece_version_type: :scene_version,
        piece_version_id: scene_v1.id,
        component_type: :world,
        component_id: story.id
      })
      |> Ash.create(authorize?: false)

    {:ok, _uc2_acked} =
      uc2
      |> Ash.Changeset.for_update(:acknowledge)
      |> Ash.update(authorize?: false)

    # other_UC — unacknowledged, but belongs to other_story's version (must NOT appear)
    {:ok, other_seq} =
      Storybox.Stories.SequencePiece
      |> Ash.Changeset.for_create(:create, %{
        title: "Other Seq",
        position: 1,
        story_id: other_story.id
      })
      |> Ash.create(authorize?: false)

    {:ok, other_seq_v1} =
      Storybox.Stories.SequenceVersion
      |> Ash.Changeset.for_create(:create, %{
        sequence_piece_id: other_seq.id,
        content_uri: "storybox://test/other/v1.fountain",
        version_number: 1,
        upstream_status: :stale,
        weights: %{}
      })
      |> Ash.create(authorize?: false)

    {:ok, _other_uc} =
      Storybox.Stories.UpstreamChange
      |> Ash.Changeset.for_create(:create, %{
        piece_version_type: :sequence_version,
        piece_version_id: other_seq_v1.id,
        component_type: :story,
        component_id: other_story.id
      })
      |> Ash.create(authorize?: false)

    %{
      story: story,
      seq_v1: seq_v1,
      uc1: uc1,
      raw_token: raw_token
    }
  end

  defp authed(conn, raw_token) do
    put_req_header(conn, "authorization", "Bearer #{raw_token}")
  end

  describe "GET /api/stories/:story_id/upstream_changes" do
    test "returns 200 with changes list", %{conn: conn, story: story, raw_token: raw_token} do
      conn =
        conn
        |> authed(raw_token)
        |> get("/api/stories/#{story.id}/upstream_changes")

      assert %{"changes" => _} = json_response(conn, 200)
    end

    test "includes only unacknowledged changes — UC1 appears, UC2 (acknowledged) does not", %{
      conn: conn,
      story: story,
      uc1: uc1,
      raw_token: raw_token
    } do
      conn =
        conn
        |> authed(raw_token)
        |> get("/api/stories/#{story.id}/upstream_changes")

      %{"changes" => changes} = json_response(conn, 200)
      ids = Enum.map(changes, & &1["id"])

      assert uc1.id in ids
      assert length(changes) == 1
    end

    test "each change includes required fields", %{
      conn: conn,
      story: story,
      uc1: uc1,
      seq_v1: seq_v1,
      raw_token: raw_token
    } do
      conn =
        conn
        |> authed(raw_token)
        |> get("/api/stories/#{story.id}/upstream_changes")

      [change] = json_response(conn, 200)["changes"]

      assert change["id"] == uc1.id
      assert change["piece_version_type"] == "sequence_version"
      assert change["piece_version_id"] == seq_v1.id
      assert change["component_type"] == "character"
      assert change["version_before"] == "v1"
      assert change["version_after"] == "v2"
      assert change["inserted_at"]
    end

    test "returns empty list for a story with no upstream changes", %{conn: conn} do
      {:ok, empty_user} =
        Storybox.Accounts.User
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: "no_changes@example.com",
          password: "password123!",
          password_confirmation: "password123!"
        })
        |> Ash.create()

      {:ok, empty_story} =
        Storybox.Stories.Story
        |> Ash.Changeset.for_create(:create, %{title: "Empty Story", user_id: empty_user.id})
        |> Ash.create()

      {:ok, empty_token, _} =
        ApiToken.generate(%{story_id: empty_story.id, user_id: empty_user.id})

      conn =
        conn
        |> authed(empty_token)
        |> get("/api/stories/#{empty_story.id}/upstream_changes")

      assert json_response(conn, 200)["changes"] == []
    end

    test "does not include upstream changes from other stories", %{
      conn: conn,
      story: story,
      raw_token: raw_token
    } do
      conn =
        conn
        |> authed(raw_token)
        |> get("/api/stories/#{story.id}/upstream_changes")

      %{"changes" => changes} = json_response(conn, 200)

      assert length(changes) == 1,
             "expected only story's own change; other_story's change leaked in"
    end

    test "returns 403 when token is scoped to a different story", %{
      conn: conn,
      raw_token: raw_token
    } do
      {:ok, other_user} =
        Storybox.Accounts.User
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: "other_uc_user@example.com",
          password: "password123!",
          password_confirmation: "password123!"
        })
        |> Ash.create()

      {:ok, wrong_story} =
        Storybox.Stories.Story
        |> Ash.Changeset.for_create(:create, %{title: "Wrong Story", user_id: other_user.id})
        |> Ash.create()

      conn =
        conn
        |> authed(raw_token)
        |> get("/api/stories/#{wrong_story.id}/upstream_changes")

      assert json_response(conn, 403)["error"] == "forbidden"
    end
  end
end
