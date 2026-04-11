defmodule StoryboxWeb.TreatmentViewTest do
  use StoryboxWeb.ConnCase

  alias Storybox.Accounts.ApiToken

  setup do
    {:ok, user} =
      Storybox.Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "treatment_view_test@example.com",
        password: "password123!",
        password_confirmation: "password123!"
      })
      |> Ash.create()

    {:ok, story} =
      Storybox.Stories.Story
      |> Ash.Changeset.for_create(:create, %{
        title: "Treatment Test Story",
        through_lines: ["preference", "tension"],
        user_id: user.id
      })
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

  defp create_piece(story, attrs) do
    {:ok, piece} =
      Storybox.Stories.SequencePiece
      |> Ash.Changeset.for_create(:create, Map.put(attrs, :story_id, story.id))
      |> Ash.create(authorize?: false)

    piece
  end

  defp create_version(piece, content) do
    {:ok, version} =
      Storybox.Stories.SequencePiece
      |> Ash.ActionInput.for_action(:create_version, %{
        sequence_piece_id: piece.id,
        content: content
      })
      |> Ash.run_action(authorize?: false)

    version
  end

  defp approve_version(piece, version) do
    {:ok, updated} =
      piece
      |> Ash.Changeset.for_update(:approve_version, %{version_id: version.id})
      |> Ash.update(authorize?: false)

    updated
  end

  # ── treatment view ──────────────────────────────────────────────────────────

  describe "GET /api/stories/:story_id/views/treatment" do
    test "returns empty acts list when story has no sequences", %{
      conn: conn,
      story: story,
      raw_token: raw_token
    } do
      conn = conn |> authed(raw_token) |> get("/api/stories/#{story.id}/views/treatment")

      body = json_response(conn, 200)
      assert body["story_id"] == story.id
      assert body["through_lines"] == ["preference", "tension"]
      assert body["acts"] == []
    end

    test "returns sequences grouped by act with approved version metadata", %{
      conn: conn,
      story: story,
      raw_token: raw_token
    } do
      p1 = create_piece(story, %{title: "Opening", act: "Act I", position: 1})
      v1 = create_version(p1, "EXT. PARK - DAY\n\nThe story begins.")
      approve_version(p1, v1)

      # Second piece in Act I — no approved version
      create_piece(story, %{title: "Complication", act: "Act I", position: 2})

      # Piece in Act II — with approved version
      p3 = create_piece(story, %{title: "Midpoint", act: "Act II", position: 1})
      v3 = create_version(p3, "INT. ROOM - NIGHT\n\nThe midpoint shift.")
      approve_version(p3, v3)

      conn = conn |> authed(raw_token) |> get("/api/stories/#{story.id}/views/treatment")

      body = json_response(conn, 200)
      acts = body["acts"]

      assert length(acts) == 2

      act1 = Enum.find(acts, &(&1["act"] == "Act I"))
      assert length(act1["sequences"]) == 2

      opening = Enum.find(act1["sequences"], &(&1["title"] == "Opening"))
      assert opening["approved_version"]["version_number"] == 1
      assert opening["approved_version"]["upstream_status"] == "current"
      assert is_map(opening["approved_version"]["weights"])

      complication = Enum.find(act1["sequences"], &(&1["title"] == "Complication"))
      assert complication["approved_version"] == nil

      act2 = Enum.find(acts, &(&1["act"] == "Act II"))
      assert length(act2["sequences"]) == 1
      assert hd(act2["sequences"])["title"] == "Midpoint"
      assert hd(act2["sequences"])["approved_version"]["version_number"] == 1
    end

    test "sequences without an act are grouped under null", %{
      conn: conn,
      story: story,
      raw_token: raw_token
    } do
      create_piece(story, %{title: "Unassigned", act: nil, position: 1})
      create_piece(story, %{title: "First Act", act: "Act I", position: 1})

      conn = conn |> authed(raw_token) |> get("/api/stories/#{story.id}/views/treatment")

      acts = json_response(conn, 200)["acts"]

      # nil act sorts last
      assert List.last(acts)["act"] == nil
      assert hd(List.last(acts)["sequences"])["title"] == "Unassigned"
    end

    test "sequences within an act are sorted by position", %{
      conn: conn,
      story: story,
      raw_token: raw_token
    } do
      create_piece(story, %{title: "Third", act: "Act I", position: 3})
      create_piece(story, %{title: "First", act: "Act I", position: 1})
      create_piece(story, %{title: "Second", act: "Act I", position: 2})

      conn = conn |> authed(raw_token) |> get("/api/stories/#{story.id}/views/treatment")

      sequences = json_response(conn, 200)["acts"] |> hd() |> Map.get("sequences")
      assert Enum.map(sequences, & &1["title"]) == ["First", "Second", "Third"]
    end

    test "response does not expose content_uri", %{
      conn: conn,
      story: story,
      raw_token: raw_token
    } do
      p = create_piece(story, %{title: "Scene", act: "Act I", position: 1})
      v = create_version(p, "content")
      approve_version(p, v)

      conn = conn |> authed(raw_token) |> get("/api/stories/#{story.id}/views/treatment")

      body = json_response(conn, 200)

      version =
        body["acts"] |> hd() |> Map.get("sequences") |> hd() |> Map.get("approved_version")

      refute Map.has_key?(version, "content_uri")
    end

    test "returns 403 when token is scoped to a different story", %{
      conn: conn,
      other_story: other_story,
      raw_token: raw_token
    } do
      conn = conn |> authed(raw_token) |> get("/api/stories/#{other_story.id}/views/treatment")
      assert json_response(conn, 403)["error"] == "forbidden"
    end
  end

  # ── sequence detail ──────────────────────────────────────────────────────────

  describe "GET /api/stories/:story_id/sequences/:id" do
    test "returns content and context for approved version", %{
      conn: conn,
      story: story,
      raw_token: raw_token
    } do
      {:ok, character} =
        Storybox.Stories.Character
        |> Ash.Changeset.for_create(:create, %{
          name: "Jane",
          essence: "A reluctant hero",
          contradictions: ["wants peace", "excels at violence"],
          voice: "Laconic",
          story_id: story.id
        })
        |> Ash.create(authorize?: false)

      {:ok, world} =
        Storybox.Stories.World
        |> Ash.Changeset.for_create(:create, %{
          history: "A world of fog",
          rules: "Magic is forbidden",
          subtext: "Power corrupts",
          story_id: story.id
        })
        |> Ash.create(authorize?: false)

      p = create_piece(story, %{title: "Opening", act: "Act I", position: 1})
      v = create_version(p, "EXT. FOREST - DAY\n\nJane walks alone.")
      approve_version(p, v)

      conn =
        conn
        |> authed(raw_token)
        |> get("/api/stories/#{story.id}/sequences/#{p.id}")

      body = json_response(conn, 200)

      assert body["id"] == p.id
      assert body["title"] == "Opening"
      assert body["act"] == "Act I"
      assert body["position"] == 1
      assert body["content"] == "EXT. FOREST - DAY\n\nJane walks alone."
      assert body["version"]["version_number"] == 1
      assert body["version"]["upstream_status"] == "current"

      assert body["context"]["world"]["id"] == world.id
      assert body["context"]["world"]["history"] == "A world of fog"

      assert length(body["context"]["characters"]) == 1
      char = hd(body["context"]["characters"])
      assert char["id"] == character.id
      assert char["name"] == "Jane"
    end

    test "falls back to latest version when no approved version is set", %{
      conn: conn,
      story: story,
      raw_token: raw_token
    } do
      p = create_piece(story, %{title: "Draft", act: "Act I", position: 1})
      create_version(p, "First draft content.")
      create_version(p, "Second draft content.")

      conn =
        conn
        |> authed(raw_token)
        |> get("/api/stories/#{story.id}/sequences/#{p.id}")

      body = json_response(conn, 200)
      assert body["version"]["version_number"] == 2
      assert body["content"] == "Second draft content."
    end

    test "returns 404 when sequence does not belong to the story", %{
      conn: conn,
      story: story,
      other_story: other_story,
      raw_token: raw_token
    } do
      other_piece = create_piece(other_story, %{title: "Foreign", act: nil, position: 1})

      conn =
        conn
        |> authed(raw_token)
        |> get("/api/stories/#{story.id}/sequences/#{other_piece.id}")

      assert json_response(conn, 404)["error"] == "not found"
    end

    test "returns 404 when sequence exists but has no versions", %{
      conn: conn,
      story: story,
      raw_token: raw_token
    } do
      p = create_piece(story, %{title: "Empty", act: nil, position: 1})

      conn =
        conn
        |> authed(raw_token)
        |> get("/api/stories/#{story.id}/sequences/#{p.id}")

      assert json_response(conn, 404)["error"] == "no version available"
    end

    test "returns 503 when MinIO object is missing", %{
      conn: conn,
      story: story,
      raw_token: raw_token
    } do
      p = create_piece(story, %{title: "Broken", act: nil, position: 1})

      {:ok, bad_version} =
        Storybox.Stories.SequenceVersion
        |> Ash.Changeset.for_create(:create, %{
          sequence_piece_id: p.id,
          content_uri:
            "storybox://stories/#{story.id}/sequences/#{p.id}/v999_nonexistent.fountain",
          version_number: 1,
          upstream_status: :current,
          weights: %{}
        })
        |> Ash.create(authorize?: false)

      p
      |> Ash.Changeset.for_update(:approve_version, %{version_id: bad_version.id})
      |> Ash.update(authorize?: false)

      conn =
        conn
        |> authed(raw_token)
        |> get("/api/stories/#{story.id}/sequences/#{p.id}")

      assert json_response(conn, 503)["error"] == "content unavailable"
    end

    test "returns 404 for a completely unknown sequence id", %{
      conn: conn,
      story: story,
      raw_token: raw_token
    } do
      conn =
        conn
        |> authed(raw_token)
        |> get("/api/stories/#{story.id}/sequences/00000000-0000-0000-0000-000000000000")

      assert json_response(conn, 404)["error"] == "not found"
    end
  end
end
