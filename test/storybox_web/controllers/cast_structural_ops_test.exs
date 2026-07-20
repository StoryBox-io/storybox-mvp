defmodule StoryboxWeb.CastStructuralOpsTest do
  use StoryboxWeb.ConnCase

  require Ash.Query

  alias Storybox.Accounts.ApiToken

  # Setup creates:
  #
  #   user ──── story ──── alice (arc written → cast position 1)
  #          │          ├── bob   (arc written → cast position 2)
  #          │          ├── cleo  (arc written → cast position 3)
  #          │          └── mute  (no arc — nothing for the cast to pin)
  #          └── other_story ── other_char
  #
  # Writing a character's through-line piece appends them to the cast stack, so
  # alice/bob/cleo land at 1/2/3. raw_token is scoped to story.

  setup do
    {:ok, user} =
      Storybox.Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "cast_structural_ops_test@example.com",
        password: "password123!",
        password_confirmation: "password123!"
      })
      |> Ash.create()

    {:ok, story} =
      Storybox.Stories.Story
      |> Ash.Changeset.for_create(:create, %{title: "Cast Story", user_id: user.id})
      |> Ash.create()

    {:ok, other_story} =
      Storybox.Stories.Story
      |> Ash.Changeset.for_create(:create, %{title: "Other Story", user_id: user.id})
      |> Ash.create()

    {:ok, raw_token, _} = ApiToken.generate(%{story_id: story.id, user_id: user.id})

    alice = create_character(story.id, "Alice")
    bob = create_character(story.id, "Bob")
    cleo = create_character(story.id, "Cleo")
    mute = create_character(story.id, "Mute")
    other_char = create_character(other_story.id, "Other")

    write_arc(raw_token, story, alice, "Alice learns to trust.")
    write_arc(raw_token, story, bob, "Bob learns to let go.")
    write_arc(raw_token, story, cleo, "Cleo learns to ask.")

    %{
      story: story,
      alice: alice,
      bob: bob,
      cleo: cleo,
      mute: mute,
      other_char: other_char,
      raw_token: raw_token
    }
  end

  defp create_character(story_id, name) do
    {:ok, character} =
      Storybox.Stories.Character
      |> Ash.Changeset.for_create(:create, %{story_id: story_id, name: name})
      |> Ash.create(authorize?: false)

    character
  end

  defp authed(conn, raw_token) do
    put_req_header(conn, "authorization", "Bearer #{raw_token}")
  end

  # Writes a character's through-line piece through the API, which cuts the
  # character view, appends them to the cast stack, and re-pins the top view.
  defp write_arc(token, story, character, content) do
    build_conn()
    |> authed(token)
    |> post("/api/stories/#{story.id}/throughline/pieces", %{
      "character_id" => character.id,
      "content" => content
    })
    |> json_response(201)
  end

  defp cast_order(story) do
    cast_view =
      Storybox.Stories.ThroughlineCastView
      |> Ash.Query.filter(story_id == ^story.id)
      |> Ash.read_one!(authorize?: false)

    cast_view.id
    |> Storybox.Stories.ThroughlineCastView.ordered_entries()
    |> Enum.map(& &1.character_id)
  end

  defp read_order(conn, token, story) do
    conn
    |> authed(token)
    |> get("/api/stories/#{story.id}/views/throughline")
    |> json_response(200)
    |> Map.fetch!("through_lines")
    |> Enum.map(& &1["character_id"])
  end

  defp top_view_cast_pin(story) do
    view =
      Storybox.Stories.ThroughlineView
      |> Ash.Query.filter(story_id == ^story.id)
      |> Ash.read_one!(authorize?: false)

    latest =
      Storybox.Stories.ThroughlineViewVersion
      |> Ash.Query.filter(throughline_view_id == ^view.id)
      |> Ash.Query.sort(version_number: :desc)
      |> Ash.Query.limit(1)
      |> Ash.read!(authorize?: false)
      |> List.first()

    pin_type = :throughline_cast_vv

    Storybox.Stories.Segment
    |> Ash.Query.filter(view_version_id == ^latest.id and pin_type == ^pin_type)
    |> Ash.read_one!(authorize?: false)
  end

  describe "POST /api/stories/:story_id/characters/:char_id/cast/insert" do
    test "201 — places a re-inserted character at the requested position", ctx do
      %{conn: conn, story: story, bob: bob, raw_token: token} = ctx

      conn
      |> authed(token)
      |> post("/api/stories/#{story.id}/characters/#{bob.id}/cast/remove")
      |> json_response(200)

      body =
        build_conn()
        |> authed(token)
        |> post("/api/stories/#{story.id}/characters/#{bob.id}/cast/insert", %{"position" => 1})
        |> json_response(201)

      assert body["character_id"] == bob.id
      assert body["position"] == 1
      assert cast_order(story) == [bob.id, ctx.alice.id, ctx.cleo.id]
    end

    test "404 — character from another story", ctx do
      %{conn: conn, story: story, other_char: other_char, raw_token: token} = ctx

      conn
      |> authed(token)
      |> post("/api/stories/#{story.id}/characters/#{other_char.id}/cast/insert", %{
        "position" => 1
      })
      |> json_response(404)
    end

    test "400 — position omitted", ctx do
      %{conn: conn, story: story, bob: bob, raw_token: token} = ctx

      conn
      |> authed(token)
      |> post("/api/stories/#{story.id}/characters/#{bob.id}/cast/insert", %{})
      |> json_response(400)
    end

    test "400 — non-positive position", ctx do
      %{conn: conn, story: story, bob: bob, raw_token: token} = ctx

      conn
      |> authed(token)
      |> post("/api/stories/#{story.id}/characters/#{bob.id}/cast/insert", %{"position" => 0})
      |> json_response(400)
    end

    test "422 — character has no through-line view", ctx do
      %{conn: conn, story: story, mute: mute, raw_token: token} = ctx

      conn
      |> authed(token)
      |> post("/api/stories/#{story.id}/characters/#{mute.id}/cast/insert", %{"position" => 1})
      |> json_response(422)

      assert cast_order(story) == [ctx.alice.id, ctx.bob.id, ctx.cleo.id]
    end

    test "409 — character already in the cast", ctx do
      %{conn: conn, story: story, bob: bob, raw_token: token} = ctx

      conn
      |> authed(token)
      |> post("/api/stories/#{story.id}/characters/#{bob.id}/cast/insert", %{"position" => 1})
      |> json_response(409)
    end

    test "422 — position past the end is rejected, not clamped", ctx do
      %{conn: conn, story: story, bob: bob, raw_token: token} = ctx

      conn
      |> authed(token)
      |> post("/api/stories/#{story.id}/characters/#{bob.id}/cast/remove")
      |> json_response(200)

      build_conn()
      |> authed(token)
      |> post("/api/stories/#{story.id}/characters/#{bob.id}/cast/insert", %{"position" => 4})
      |> json_response(422)

      assert cast_order(story) == [ctx.alice.id, ctx.cleo.id]
    end
  end

  describe "POST /api/stories/:story_id/characters/:char_id/cast/reorder" do
    test "200 — moves an entry, leaving the others' relative order intact", ctx do
      %{conn: conn, story: story, cleo: cleo, raw_token: token} = ctx

      body =
        conn
        |> authed(token)
        |> post("/api/stories/#{story.id}/characters/#{cleo.id}/cast/reorder", %{
          "new_position" => 1
        })
        |> json_response(200)

      assert body["character_id"] == cleo.id
      assert body["position"] == 1
      assert cast_order(story) == [cleo.id, ctx.alice.id, ctx.bob.id]
    end

    test "404 — character from another story", ctx do
      %{conn: conn, story: story, other_char: other_char, raw_token: token} = ctx

      conn
      |> authed(token)
      |> post("/api/stories/#{story.id}/characters/#{other_char.id}/cast/reorder", %{
        "new_position" => 1
      })
      |> json_response(404)
    end

    test "400 — new_position is not a positive integer", ctx do
      %{conn: conn, story: story, bob: bob, raw_token: token} = ctx

      conn
      |> authed(token)
      |> post("/api/stories/#{story.id}/characters/#{bob.id}/cast/reorder", %{
        "new_position" => "second"
      })
      |> json_response(400)
    end

    test "422 — new_position out of range", ctx do
      %{conn: conn, story: story, bob: bob, raw_token: token} = ctx

      conn
      |> authed(token)
      |> post("/api/stories/#{story.id}/characters/#{bob.id}/cast/reorder", %{"new_position" => 4})
      |> json_response(422)

      assert cast_order(story) == [ctx.alice.id, ctx.bob.id, ctx.cleo.id]
    end

    test "422 — character not in the cast", ctx do
      %{conn: conn, story: story, mute: mute, raw_token: token} = ctx

      conn
      |> authed(token)
      |> post("/api/stories/#{story.id}/characters/#{mute.id}/cast/reorder", %{
        "new_position" => 1
      })
      |> json_response(422)
    end
  end

  describe "POST /api/stories/:story_id/characters/:char_id/cast/remove" do
    test "200 — drops the entry and closes the gap", ctx do
      %{conn: conn, story: story, alice: alice, raw_token: token} = ctx

      body =
        conn
        |> authed(token)
        |> post("/api/stories/#{story.id}/characters/#{alice.id}/cast/remove")
        |> json_response(200)

      assert body["character_id"] == alice.id
      refute Map.has_key?(body, "position")
      assert cast_order(story) == [ctx.bob.id, ctx.cleo.id]
    end

    test "200 — the character's own arc is still readable afterwards", ctx do
      %{conn: conn, story: story, alice: alice, raw_token: token} = ctx

      conn
      |> authed(token)
      |> post("/api/stories/#{story.id}/characters/#{alice.id}/cast/remove")
      |> json_response(200)

      piece =
        Storybox.Stories.ThroughlinePiece
        |> Ash.Query.filter(character_id == ^alice.id)
        |> Ash.read_one!(authorize?: false)

      body =
        build_conn()
        |> authed(token)
        |> get("/api/stories/#{story.id}/pieces/throughline/#{piece.id}")
        |> json_response(200)

      assert body["content"] == "Alice learns to trust."
    end

    test "404 — character from another story", ctx do
      %{conn: conn, story: story, other_char: other_char, raw_token: token} = ctx

      conn
      |> authed(token)
      |> post("/api/stories/#{story.id}/characters/#{other_char.id}/cast/remove")
      |> json_response(404)
    end

    test "422 — character not in the cast", ctx do
      %{conn: conn, story: story, mute: mute, raw_token: token} = ctx

      conn
      |> authed(token)
      |> post("/api/stories/#{story.id}/characters/#{mute.id}/cast/remove")
      |> json_response(422)
    end
  end

  describe "cast ops and the through-line read" do
    test "each op cuts a new cast version and re-pins the top view at it", ctx do
      %{conn: conn, story: story, cleo: cleo, raw_token: token} = ctx

      before_pin = top_view_cast_pin(story)

      conn
      |> authed(token)
      |> post("/api/stories/#{story.id}/characters/#{cleo.id}/cast/reorder", %{
        "new_position" => 1
      })
      |> json_response(200)

      after_pin = top_view_cast_pin(story)

      refute after_pin.pin_id == before_pin.pin_id
      assert after_pin.pin_version_at_creation == before_pin.pin_version_at_creation + 1
    end

    test "a prior cast version keeps its segments", ctx do
      %{conn: conn, story: story, cleo: cleo, raw_token: token} = ctx

      before_pin = top_view_cast_pin(story)

      conn
      |> authed(token)
      |> post("/api/stories/#{story.id}/characters/#{cleo.id}/cast/reorder", %{
        "new_position" => 1
      })
      |> json_response(200)

      assert before_pin.pin_id
             |> Storybox.Stories.ThroughlineCastView.entries_for_version()
             |> Enum.map(& &1.character_id) == [ctx.alice.id, ctx.bob.id, ctx.cleo.id]
    end

    test "the read reflects the new order after each op", ctx do
      %{conn: conn, story: story, alice: alice, bob: bob, cleo: cleo, raw_token: token} = ctx

      assert read_order(conn, token, story) == [alice.id, bob.id, cleo.id]

      build_conn()
      |> authed(token)
      |> post("/api/stories/#{story.id}/characters/#{cleo.id}/cast/reorder", %{
        "new_position" => 1
      })
      |> json_response(200)

      assert read_order(build_conn(), token, story) == [cleo.id, alice.id, bob.id]

      build_conn()
      |> authed(token)
      |> post("/api/stories/#{story.id}/characters/#{alice.id}/cast/remove")
      |> json_response(200)

      assert read_order(build_conn(), token, story) == [cleo.id, bob.id]

      build_conn()
      |> authed(token)
      |> post("/api/stories/#{story.id}/characters/#{alice.id}/cast/insert", %{"position" => 2})
      |> json_response(201)

      assert read_order(build_conn(), token, story) == [cleo.id, alice.id, bob.id]
    end
  end
end
