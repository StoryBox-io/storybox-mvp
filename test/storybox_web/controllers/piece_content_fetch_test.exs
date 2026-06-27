defmodule StoryboxWeb.PieceContentFetchTest do
  use StoryboxWeb.ConnCase

  alias Storybox.Accounts.ApiToken

  require Ash.Query

  # Per-version Piece content fetch (issue #192).
  #
  # Setup builds, under one story, a version-1 piece of every type (and a
  # version-2 SynopsisPiece, to prove non-latest versions stay addressable),
  # plus an other_story SynopsisPiece for the cross-story ownership boundary.
  #
  #   story ── sequence ── SynopsisPiece v1 + v2, SequencePiece v1
  #         ├─ scene     ── ScriptPiece v1
  #         ├─ character ── CharacterPiece v1
  #         ├─ world     ── WorldPiece v1
  #         └─ (story)   ── ThroughlinePiece v1 (controlling idea)
  #
  #   other_story ── other_sequence ── SynopsisPiece v1
  #
  # raw_token is scoped to story; raw_token_other to other_story.

  setup do
    {:ok, user} =
      Storybox.Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "piece_content_fetch_test@example.com",
        password: "password123!",
        password_confirmation: "password123!"
      })
      |> Ash.create()

    {:ok, story} =
      Storybox.Stories.Story
      |> Ash.Changeset.for_create(:create, %{title: "Fetch Story", user_id: user.id})
      |> Ash.create()

    {:ok, other_story} =
      Storybox.Stories.Story
      |> Ash.Changeset.for_create(:create, %{title: "Other Story", user_id: user.id})
      |> Ash.create()

    {:ok, raw_token, _} = ApiToken.generate(%{story_id: story.id, user_id: user.id})
    {:ok, raw_token_other, _} = ApiToken.generate(%{story_id: other_story.id, user_id: user.id})

    {:ok, sequence} =
      Storybox.Stories.Sequence
      |> Ash.Changeset.for_create(:create, %{story_id: story.id, name: "Seq", slug: "seq"})
      |> Ash.create(authorize?: false)

    {:ok, synopsis_v1} =
      Storybox.Stories.SynopsisPiece
      |> Ash.ActionInput.for_action(:create_version, %{
        story_id: story.id,
        sequence_id: sequence.id,
        content: "Synopsis v1."
      })
      |> Ash.run_action(authorize?: false)

    {:ok, synopsis_v2} =
      Storybox.Stories.SynopsisPiece
      |> Ash.ActionInput.for_action(:create_version, %{
        story_id: story.id,
        sequence_id: sequence.id,
        content: "Synopsis v2."
      })
      |> Ash.run_action(authorize?: false)

    {:ok, sequence_piece} =
      Storybox.Stories.SequencePiece
      |> Ash.ActionInput.for_action(:create_version, %{
        story_id: story.id,
        sequence_id: sequence.id,
        content: "Sequence prose."
      })
      |> Ash.run_action(authorize?: false)

    {:ok, scene} =
      Storybox.Stories.Scene
      |> Ash.Changeset.for_create(:create, %{slug: "scene", story_id: story.id})
      |> Ash.create(authorize?: false)

    {:ok, script_piece} =
      Storybox.Stories.ScriptPiece
      |> Ash.ActionInput.for_action(:create_version, %{
        scene_id: scene.id,
        content: "INT. OFFICE - DAY\nScript body."
      })
      |> Ash.run_action(authorize?: false)

    {:ok, character} =
      Storybox.Stories.Character
      |> Ash.Changeset.for_create(:create, %{name: "Akko", story_id: story.id})
      |> Ash.create(authorize?: false)

    {:ok, character_piece} =
      Storybox.Stories.CharacterPiece
      |> Ash.ActionInput.for_action(:create_version, %{
        character_id: character.id,
        content: "Character notes."
      })
      |> Ash.run_action(authorize?: false)

    {:ok, world} =
      Storybox.Stories.World
      |> Ash.Changeset.for_create(:create, %{name: "World", story_id: story.id})
      |> Ash.create(authorize?: false)

    {:ok, world_piece} =
      Storybox.Stories.WorldPiece
      |> Ash.ActionInput.for_action(:create_version, %{
        world_id: world.id,
        content: "World bible."
      })
      |> Ash.run_action(authorize?: false)

    {:ok, throughline_piece} =
      Storybox.Stories.ThroughlinePiece
      |> Ash.ActionInput.for_action(:create_version, %{
        story_id: story.id,
        character_id: nil,
        content: "The controlling idea."
      })
      |> Ash.run_action(authorize?: false)

    # A piece in another story, used for the cross-story ownership boundary.
    {:ok, other_sequence} =
      Storybox.Stories.Sequence
      |> Ash.Changeset.for_create(:create, %{
        story_id: other_story.id,
        name: "Other Seq",
        slug: "other-seq"
      })
      |> Ash.create(authorize?: false)

    {:ok, other_synopsis} =
      Storybox.Stories.SynopsisPiece
      |> Ash.ActionInput.for_action(:create_version, %{
        story_id: other_story.id,
        sequence_id: other_sequence.id,
        content: "Other story synopsis."
      })
      |> Ash.run_action(authorize?: false)

    %{
      story: story,
      other_story: other_story,
      raw_token: raw_token,
      raw_token_other: raw_token_other,
      synopsis_v1: synopsis_v1,
      synopsis_v2: synopsis_v2,
      sequence_piece: sequence_piece,
      script_piece: script_piece,
      character_piece: character_piece,
      world_piece: world_piece,
      throughline_piece: throughline_piece,
      other_synopsis: other_synopsis
    }
  end

  describe "GET /api/stories/:story_id/pieces/:piece_type/:piece_id — 200 per type" do
    test "synopsis", %{conn: conn, story: story, raw_token: token, synopsis_v2: piece} do
      body = fetch(conn, token, story, "synopsis", piece.id, 200)
      assert body["piece_id"] == piece.id
      assert body["piece_type"] == "synopsis"
      assert body["version_number"] == 2
      assert body["content"] == "Synopsis v2."
    end

    test "sequence", %{conn: conn, story: story, raw_token: token, sequence_piece: piece} do
      body = fetch(conn, token, story, "sequence", piece.id, 200)
      assert body["piece_type"] == "sequence"
      assert body["content"] == "Sequence prose."
    end

    test "script", %{conn: conn, story: story, raw_token: token, script_piece: piece} do
      body = fetch(conn, token, story, "script", piece.id, 200)
      assert body["piece_type"] == "script"
      assert body["content"] == "INT. OFFICE - DAY\nScript body."
    end

    test "character", %{conn: conn, story: story, raw_token: token, character_piece: piece} do
      body = fetch(conn, token, story, "character", piece.id, 200)
      assert body["piece_type"] == "character"
      assert body["content"] == "Character notes."
    end

    test "world", %{conn: conn, story: story, raw_token: token, world_piece: piece} do
      body = fetch(conn, token, story, "world", piece.id, 200)
      assert body["piece_type"] == "world"
      assert body["content"] == "World bible."
    end

    test "throughline", %{conn: conn, story: story, raw_token: token, throughline_piece: piece} do
      body = fetch(conn, token, story, "throughline", piece.id, 200)
      assert body["piece_type"] == "throughline"
      assert body["content"] == "The controlling idea."
    end
  end

  describe "per-version addressing" do
    test "a non-latest version is still fetchable by its id", %{
      conn: conn,
      story: story,
      raw_token: token,
      synopsis_v1: v1
    } do
      body = fetch(conn, token, story, "synopsis", v1.id, 200)
      assert body["version_number"] == 1
      assert body["content"] == "Synopsis v1."
    end
  end

  describe "ownership boundary" do
    test "404 when the piece belongs to a different story", %{
      conn: conn,
      story: story,
      raw_token: token,
      other_synopsis: other
    } do
      body = fetch(conn, token, story, "synopsis", other.id, 404)
      assert body["error"] == "not found"
    end

    test "404 for a parent-chain piece (script) owned by another story", %{
      conn: conn,
      story: story,
      other_story: other_story,
      raw_token: token
    } do
      {:ok, other_scene} =
        Storybox.Stories.Scene
        |> Ash.Changeset.for_create(:create, %{slug: "x", story_id: other_story.id})
        |> Ash.create(authorize?: false)

      {:ok, other_script} =
        Storybox.Stories.ScriptPiece
        |> Ash.ActionInput.for_action(:create_version, %{
          scene_id: other_scene.id,
          content: "Other script."
        })
        |> Ash.run_action(authorize?: false)

      body = fetch(conn, token, story, "script", other_script.id, 404)
      assert body["error"] == "not found"
    end
  end

  describe "error handling" do
    test "400 for an unknown piece_type", %{conn: conn, story: story, raw_token: token} do
      body =
        fetch(conn, token, story, "bogus", "00000000-0000-0000-0000-000000000000", 400)

      assert body["error"] == "unknown piece_type"
    end

    test "404 for a valid-but-absent piece_id", %{conn: conn, story: story, raw_token: token} do
      body =
        fetch(conn, token, story, "synopsis", "00000000-0000-0000-0000-000000000000", 404)

      assert body["error"] == "not found"
    end

    test "503 when stored content is unavailable", %{
      conn: conn,
      story: story,
      raw_token: token,
      synopsis_v1: existing
    } do
      # A piece row whose content_uri was never written to storage.
      {:ok, orphan} =
        Storybox.Stories.SynopsisPiece
        |> Ash.Changeset.for_create(:create, %{
          story_id: story.id,
          sequence_id: existing.sequence_id,
          content_uri: "storybox://stories/#{story.id}/synopsis/orphan/v999",
          version_number: 999
        })
        |> Ash.create(authorize?: false)

      body = fetch(conn, token, story, "synopsis", orphan.id, 503)
      assert body["error"] == "content unavailable"
    end

    test "401 without a token", %{conn: conn, story: story, synopsis_v1: piece} do
      conn = get(conn, "/api/stories/#{story.id}/pieces/synopsis/#{piece.id}")
      assert json_response(conn, 401)
    end

    test "403 when the token story does not match the path story_id", %{
      conn: conn,
      story: story,
      raw_token_other: token_other,
      synopsis_v1: piece
    } do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token_other}")
        |> get("/api/stories/#{story.id}/pieces/synopsis/#{piece.id}")

      assert json_response(conn, 403)
    end
  end

  defp fetch(conn, token, story, type, id, status) do
    conn
    |> put_req_header("authorization", "Bearer #{token}")
    |> get("/api/stories/#{story.id}/pieces/#{type}/#{id}")
    |> json_response(status)
  end
end
