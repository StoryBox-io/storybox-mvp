defmodule StoryboxWeb.CutViewVersionTest do
  use StoryboxWeb.ConnCase

  alias Storybox.Accounts.ApiToken

  require Ash.Query

  # Lazy bootstrap (BootstrapStory) creates only TreatmentView, SynopsisView, and
  # an empty StorySpine — no Sequences and no layer VVs.
  #
  # Setup builds on top of that:
  #   one Sequence (registers a StorySpine entry on create)
  #   StoryScriptView
  #   SequenceView for that Sequence
  #   Scene + ScriptView + ScriptPiece v1
  #
  # other_story exists only for 403/404 cross-story tests.
  # raw_token scoped to story; raw_token_other scoped to other_story.

  setup do
    {:ok, user} =
      Storybox.Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "cut_vv_test@example.com",
        password: "password123!",
        password_confirmation: "password123!"
      })
      |> Ash.create()

    {:ok, story} =
      Storybox.Stories.Story
      |> Ash.Changeset.for_create(:create, %{title: "Cut VV Story", user_id: user.id})
      |> Ash.create()

    {:ok, other_story} =
      Storybox.Stories.Story
      |> Ash.Changeset.for_create(:create, %{title: "Other Story", user_id: user.id})
      |> Ash.create()

    {:ok, raw_token, _} = ApiToken.generate(%{story_id: story.id, user_id: user.id})
    {:ok, raw_token_other, _} = ApiToken.generate(%{story_id: other_story.id, user_id: user.id})

    # Lazy bootstrap creates no Sequence — make one per story (each registers a
    # StorySpine entry on create).
    {:ok, sequence} =
      Storybox.Stories.Sequence
      |> Ash.Changeset.for_create(:create, %{
        story_id: story.id,
        name: "Sequence 1",
        slug: "sequence-1"
      })
      |> Ash.create(authorize?: false)

    {:ok, other_sequence} =
      Storybox.Stories.Sequence
      |> Ash.Changeset.for_create(:create, %{
        story_id: other_story.id,
        name: "Sequence 1",
        slug: "sequence-1"
      })
      |> Ash.create(authorize?: false)

    # StoryScriptView is not bootstrapped — create it for the story_script cut test
    {:ok, _story_script_view} =
      Storybox.Stories.StoryScriptView
      |> Ash.Changeset.for_create(:create, %{story_id: story.id})
      |> Ash.create(authorize?: false)

    # SequenceView is not bootstrapped — create it for the sequence cut test
    {:ok, _sequence_view} =
      Storybox.Stories.SequenceView
      |> Ash.Changeset.for_create(:create, %{sequence_id: sequence.id, story_id: story.id})
      |> Ash.create(authorize?: false)

    {:ok, scene} =
      Storybox.Stories.Scene
      |> Ash.Changeset.for_create(:create, %{slug: "scene-1", story_id: story.id})
      |> Ash.create(authorize?: false)

    {:ok, _script_view} =
      Storybox.Stories.ScriptView
      |> Ash.Changeset.for_create(:create, %{scene_id: scene.id})
      |> Ash.create(authorize?: false)

    {:ok, script_piece} =
      Storybox.Stories.ScriptPiece
      |> Ash.Changeset.for_create(:create, %{
        scene_id: scene.id,
        content_uri: Storybox.Storage.uri_for_script_piece(scene.id, 1),
        version_number: 1,
        weights: %{}
      })
      |> Ash.create(authorize?: false)

    %{
      story: story,
      other_story: other_story,
      sequence: sequence,
      other_sequence: other_sequence,
      scene: scene,
      script_piece: script_piece,
      raw_token: raw_token,
      raw_token_other: raw_token_other
    }
  end

  describe "POST /api/stories/:story_id/views/synopsis/cut" do
    test "201 with id, version_number 1, and unresolvable_segments for nil-pin sequences", %{
      conn: conn,
      story: story,
      raw_token: token
    } do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> post("/api/stories/#{story.id}/views/synopsis/cut")

      body = json_response(conn, 201)
      assert body["id"]
      # lazy bootstrap cuts no SVV; this is the first cut → v1
      assert body["version_number"] == 1
      # the setup sequence has no SynopsisPiece → one unresolvable segment
      assert length(body["unresolvable_segments"]) == 1
      [seg] = body["unresolvable_segments"]
      assert seg["position"] == 1
    end

    test "401 without token", %{conn: conn, story: story} do
      conn = post(conn, "/api/stories/#{story.id}/views/synopsis/cut")
      assert json_response(conn, 401)
    end

    test "403 when token story does not match path story_id", %{
      conn: conn,
      story: story,
      raw_token_other: token_other
    } do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token_other}")
        |> post("/api/stories/#{story.id}/views/synopsis/cut")

      assert json_response(conn, 403)
    end
  end

  describe "POST /api/stories/:story_id/views/treatment/cut" do
    test "201 with version_number 1 (first TreatmentVV cut)", %{
      conn: conn,
      story: story,
      raw_token: token
    } do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> post("/api/stories/#{story.id}/views/treatment/cut")

      body = json_response(conn, 201)
      assert body["id"]
      assert body["version_number"] == 1
      assert is_list(body["unresolvable_segments"])
    end

    test "401 without token", %{conn: conn, story: story} do
      conn = post(conn, "/api/stories/#{story.id}/views/treatment/cut")
      assert json_response(conn, 401)
    end

    test "403 when token story does not match path story_id", %{
      conn: conn,
      story: story,
      raw_token_other: token_other
    } do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token_other}")
        |> post("/api/stories/#{story.id}/views/treatment/cut")

      assert json_response(conn, 403)
    end
  end

  describe "POST /api/stories/:story_id/views/story_script/cut" do
    test "201 with version_number 1 (first StoryScriptVV cut)", %{
      conn: conn,
      story: story,
      raw_token: token
    } do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> post("/api/stories/#{story.id}/views/story_script/cut")

      body = json_response(conn, 201)
      assert body["id"]
      assert body["version_number"] == 1
      assert is_list(body["unresolvable_segments"])
    end

    test "401 without token", %{conn: conn, story: story} do
      conn = post(conn, "/api/stories/#{story.id}/views/story_script/cut")
      assert json_response(conn, 401)
    end

    test "403 when token story does not match path story_id", %{
      conn: conn,
      story: story,
      raw_token_other: token_other
    } do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token_other}")
        |> post("/api/stories/#{story.id}/views/story_script/cut")

      assert json_response(conn, 403)
    end
  end

  describe "POST /api/stories/:story_id/sequences/:seq_id/views/sequence/cut" do
    test "201 with empty script_view_version_ids list", %{
      conn: conn,
      story: story,
      sequence: sequence,
      raw_token: token
    } do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> post(
          "/api/stories/#{story.id}/sequences/#{sequence.id}/views/sequence/cut",
          %{"script_view_version_ids" => []}
        )

      body = json_response(conn, 201)
      assert body["id"]
      assert body["version_number"] == 1
      assert body["unresolvable_segments"] == []
    end

    test "201 when body omits script_view_version_ids (defaults to [])", %{
      conn: conn,
      story: story,
      sequence: sequence,
      raw_token: token
    } do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> post("/api/stories/#{story.id}/sequences/#{sequence.id}/views/sequence/cut", %{})

      body = json_response(conn, 201)
      assert body["version_number"] == 1
      assert body["unresolvable_segments"] == []
    end

    test "404 when seq_id belongs to a different story", %{
      conn: conn,
      story: story,
      other_sequence: other_sequence,
      raw_token: token
    } do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> post(
          "/api/stories/#{story.id}/sequences/#{other_sequence.id}/views/sequence/cut",
          %{}
        )

      assert json_response(conn, 404)
    end

    test "401 without token", %{conn: conn, story: story, sequence: sequence} do
      conn =
        post(conn, "/api/stories/#{story.id}/sequences/#{sequence.id}/views/sequence/cut", %{})

      assert json_response(conn, 401)
    end

    test "403 when token story does not match path story_id", %{
      conn: conn,
      story: story,
      sequence: sequence,
      raw_token_other: token_other
    } do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token_other}")
        |> post(
          "/api/stories/#{story.id}/sequences/#{sequence.id}/views/sequence/cut",
          %{}
        )

      assert json_response(conn, 403)
    end
  end

  describe "POST /api/stories/:story_id/scenes/:scene_id/views/script/cut" do
    test "201 with unresolvable_segments empty (script piece pinned)", %{
      conn: conn,
      story: story,
      scene: scene,
      script_piece: piece,
      raw_token: token
    } do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> post(
          "/api/stories/#{story.id}/scenes/#{scene.id}/views/script/cut",
          %{"script_piece_id" => piece.id}
        )

      body = json_response(conn, 201)
      assert body["id"]
      assert body["version_number"] == 1
      assert body["unresolvable_segments"] == []
    end

    test "400 when script_piece_id is missing", %{
      conn: conn,
      story: story,
      scene: scene,
      raw_token: token
    } do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> post("/api/stories/#{story.id}/scenes/#{scene.id}/views/script/cut", %{})

      assert json_response(conn, 400)["error"] =~ "script_piece_id"
    end

    test "404 when scene_id does not exist", %{
      conn: conn,
      story: story,
      script_piece: piece,
      raw_token: token
    } do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> post(
          "/api/stories/#{story.id}/scenes/00000000-0000-0000-0000-000000000000/views/script/cut",
          %{"script_piece_id" => piece.id}
        )

      assert json_response(conn, 404)
    end

    test "404 when script_piece_id does not belong to the scene", %{
      conn: conn,
      story: story,
      scene: scene,
      raw_token: token
    } do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> post(
          "/api/stories/#{story.id}/scenes/#{scene.id}/views/script/cut",
          %{"script_piece_id" => "00000000-0000-0000-0000-000000000000"}
        )

      assert json_response(conn, 404)
    end

    test "401 without token", %{conn: conn, story: story, scene: scene, script_piece: piece} do
      conn =
        post(
          conn,
          "/api/stories/#{story.id}/scenes/#{scene.id}/views/script/cut",
          %{"script_piece_id" => piece.id}
        )

      assert json_response(conn, 401)
    end

    test "403 when token story does not match path story_id", %{
      conn: conn,
      story: story,
      scene: scene,
      script_piece: piece,
      raw_token_other: token_other
    } do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token_other}")
        |> post(
          "/api/stories/#{story.id}/scenes/#{scene.id}/views/script/cut",
          %{"script_piece_id" => piece.id}
        )

      assert json_response(conn, 403)
    end
  end
end
