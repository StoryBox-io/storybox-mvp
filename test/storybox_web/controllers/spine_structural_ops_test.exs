defmodule StoryboxWeb.SpineStructuralOpsTest do
  use StoryboxWeb.ConnCase

  require Ash.Query

  alias Storybox.Accounts.ApiToken

  # Setup creates:
  #
  #   user ──── story ──── seq_a (spine pos 1)
  #          │          ├── seq_b (spine pos 2)
  #          │          └── seq_c (spine pos 3)
  #          └── other_story ── other_seq
  #
  # Sequences are created OFF the spine, so the helper explicitly places each on
  # the Story's spine at the tail, landing seq_a/seq_b/seq_c at positions 1/2/3.
  # raw_token is scoped to story.

  setup do
    {:ok, user} =
      Storybox.Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "spine_structural_ops_test@example.com",
        password: "password123!",
        password_confirmation: "password123!"
      })
      |> Ash.create()

    {:ok, story} =
      Storybox.Stories.Story
      |> Ash.Changeset.for_create(:create, %{title: "Spine Story", user_id: user.id})
      |> Ash.create()

    {:ok, other_story} =
      Storybox.Stories.Story
      |> Ash.Changeset.for_create(:create, %{title: "Other Story", user_id: user.id})
      |> Ash.create()

    seq_a = create_sequence(story.id, "Seq A", "seq-a")
    seq_b = create_sequence(story.id, "Seq B", "seq-b")
    seq_c = create_sequence(story.id, "Seq C", "seq-c")
    other_seq = create_sequence(other_story.id, "Other Seq", "other-seq")

    {:ok, raw_token, _} = ApiToken.generate(%{story_id: story.id, user_id: user.id})

    %{
      story: story,
      other_story: other_story,
      seq_a: seq_a,
      seq_b: seq_b,
      seq_c: seq_c,
      other_seq: other_seq,
      raw_token: raw_token
    }
  end

  # Creates a Sequence off-spine, then places it at the tail of the story's
  # spine (creating the spine if absent), mirroring the old create side effect.
  defp create_sequence(story_id, name, slug) do
    {:ok, seq} =
      Storybox.Stories.Sequence
      |> Ash.Changeset.for_create(:create, %{story_id: story_id, name: name, slug: slug})
      |> Ash.create(authorize?: false)

    {:ok, spine} =
      Storybox.Stories.StorySpine
      |> Ash.ActionInput.for_action(:ensure_for_story, %{story_id: story_id})
      |> Ash.run_action(authorize?: false)

    Storybox.Stories.StorySpine
    |> Ash.ActionInput.for_action(:add_entry, %{
      story_spine_id: spine.id,
      sequence_id: seq.id
    })
    |> Ash.run_action!(authorize?: false)

    seq
  end

  # Remove a sequence from a story's spine via the resource action (repacks).
  defp remove_from_spine(story_id, sequence_id) do
    spine =
      Storybox.Stories.StorySpine
      |> Ash.Query.filter(story_id == ^story_id)
      |> Ash.read_one!(authorize?: false)

    Storybox.Stories.StorySpine
    |> Ash.ActionInput.for_action(:remove_entry, %{
      story_spine_id: spine.id,
      sequence_id: sequence_id
    })
    |> Ash.run_action!(authorize?: false)
  end

  # Returns the spine order as a list of {sequence_id, position} tuples, sorted.
  defp spine_order(story_id) do
    spine =
      Storybox.Stories.StorySpine
      |> Ash.Query.filter(story_id == ^story_id)
      |> Ash.read_one!(authorize?: false)

    Storybox.Stories.StorySpineEntry
    |> Ash.Query.filter(story_spine_id == ^spine.id)
    |> Ash.Query.sort(:position)
    |> Ash.read!(authorize?: false)
    |> Enum.map(&{&1.sequence_id, &1.position})
  end

  defp positions(story_id), do: story_id |> spine_order() |> Enum.map(&elem(&1, 1))

  defp auth(conn, token), do: put_req_header(conn, "authorization", "Bearer #{token}")

  describe "POST .../spine/insert" do
    test "with no body appends the sequence at the tail", %{
      conn: conn,
      story: story,
      seq_a: seq_a,
      raw_token: raw_token
    } do
      remove_from_spine(story.id, seq_a.id)
      # spine now: seq_b(1), seq_c(2)

      conn =
        conn
        |> auth(raw_token)
        |> post("/api/stories/#{story.id}/sequences/#{seq_a.id}/spine/insert", %{})

      body = json_response(conn, 201)
      assert body["sequence_id"] == seq_a.id
      assert body["position"] == 3
      assert positions(story.id) == [1, 2, 3]
      assert List.last(spine_order(story.id)) == {seq_a.id, 3}
    end

    test "with position: 1 inserts at head and repacks densely", %{
      conn: conn,
      story: story,
      seq_a: seq_a,
      raw_token: raw_token
    } do
      remove_from_spine(story.id, seq_a.id)
      # spine now: seq_b(1), seq_c(2)

      conn =
        conn
        |> auth(raw_token)
        |> post("/api/stories/#{story.id}/sequences/#{seq_a.id}/spine/insert", %{
          "position" => 1
        })

      body = json_response(conn, 201)
      assert body["position"] == 1
      assert positions(story.id) == [1, 2, 3]
      assert hd(spine_order(story.id)) == {seq_a.id, 1}
    end

    test "with an out-of-range position clamps to the end", %{
      conn: conn,
      story: story,
      seq_a: seq_a,
      raw_token: raw_token
    } do
      remove_from_spine(story.id, seq_a.id)

      conn =
        conn
        |> auth(raw_token)
        |> post("/api/stories/#{story.id}/sequences/#{seq_a.id}/spine/insert", %{
          "position" => 99
        })

      body = json_response(conn, 201)
      assert body["position"] == 3
      assert positions(story.id) == [1, 2, 3]
    end

    test "with a non-positive or non-integer position returns 400", %{
      story: story,
      seq_a: seq_a,
      raw_token: raw_token
    } do
      remove_from_spine(story.id, seq_a.id)

      for bad <- [0, -1, "abc"] do
        conn =
          build_conn()
          |> auth(raw_token)
          |> post("/api/stories/#{story.id}/sequences/#{seq_a.id}/spine/insert", %{
            "position" => bad
          })

        assert json_response(conn, 400)["error"] == "position must be a positive integer"
      end
    end

    test "inserting a sequence already on the spine returns 409", %{
      conn: conn,
      story: story,
      seq_b: seq_b,
      raw_token: raw_token
    } do
      conn =
        conn
        |> auth(raw_token)
        |> post("/api/stories/#{story.id}/sequences/#{seq_b.id}/spine/insert", %{})

      assert json_response(conn, 409)["error"] == "sequence already on spine"
    end

    test "inserting a sequence from another story returns 404", %{
      conn: conn,
      story: story,
      other_seq: other_seq,
      raw_token: raw_token
    } do
      conn =
        conn
        |> auth(raw_token)
        |> post("/api/stories/#{story.id}/sequences/#{other_seq.id}/spine/insert", %{})

      assert json_response(conn, 404)["error"] == "not found"
    end
  end

  describe "POST .../spine/reorder" do
    test "moves the sequence to the head and repacks densely", %{
      conn: conn,
      story: story,
      seq_c: seq_c,
      raw_token: raw_token
    } do
      conn =
        conn
        |> auth(raw_token)
        |> post("/api/stories/#{story.id}/sequences/#{seq_c.id}/spine/reorder", %{
          "position" => 1
        })

      body = json_response(conn, 200)
      assert body["sequence_id"] == seq_c.id
      assert body["position"] == 1
      assert positions(story.id) == [1, 2, 3]
      assert hd(spine_order(story.id)) == {seq_c.id, 1}
    end

    test "clamps an out-of-range position to the last slot", %{
      conn: conn,
      story: story,
      seq_a: seq_a,
      raw_token: raw_token
    } do
      conn =
        conn
        |> auth(raw_token)
        |> post("/api/stories/#{story.id}/sequences/#{seq_a.id}/spine/reorder", %{
          "position" => 99
        })

      body = json_response(conn, 200)
      assert body["position"] == 3
      assert positions(story.id) == [1, 2, 3]
      assert List.last(spine_order(story.id)) == {seq_a.id, 3}
    end

    test "reordering a sequence not on the spine returns 422", %{
      conn: conn,
      story: story,
      seq_a: seq_a,
      raw_token: raw_token
    } do
      remove_from_spine(story.id, seq_a.id)

      conn =
        conn
        |> auth(raw_token)
        |> post("/api/stories/#{story.id}/sequences/#{seq_a.id}/spine/reorder", %{
          "position" => 1
        })

      assert json_response(conn, 422)["error"] == "sequence not on spine"
    end

    test "missing or non-integer position returns 400", %{
      story: story,
      seq_a: seq_a,
      raw_token: raw_token
    } do
      for params <- [%{}, %{"position" => "x"}, %{"position" => 0}] do
        conn =
          build_conn()
          |> auth(raw_token)
          |> post("/api/stories/#{story.id}/sequences/#{seq_a.id}/spine/reorder", params)

        assert json_response(conn, 400)["error"] == "position must be a positive integer"
      end
    end
  end

  describe "POST .../spine/remove" do
    test "removes the entry and repacks remaining positions densely", %{
      conn: conn,
      story: story,
      seq_a: seq_a,
      seq_b: seq_b,
      seq_c: seq_c,
      raw_token: raw_token
    } do
      conn =
        conn
        |> auth(raw_token)
        |> post("/api/stories/#{story.id}/sequences/#{seq_a.id}/spine/remove", %{})

      assert json_response(conn, 200)["sequence_id"] == seq_a.id
      assert spine_order(story.id) == [{seq_b.id, 1}, {seq_c.id, 2}]
    end

    test "leaves the sequence's Pieces intact", %{
      conn: conn,
      story: story,
      seq_a: seq_a,
      raw_token: raw_token
    } do
      {:ok, _piece} =
        Storybox.Stories.SequencePiece
        |> Ash.Changeset.for_create(:create, %{
          story_id: story.id,
          sequence_id: seq_a.id,
          content_uri: "seq/#{seq_a.id}/1.fountain",
          version_number: 1,
          weights: %{}
        })
        |> Ash.create(authorize?: false)

      conn
      |> auth(raw_token)
      |> post("/api/stories/#{story.id}/sequences/#{seq_a.id}/spine/remove", %{})

      pieces =
        Storybox.Stories.SequencePiece
        |> Ash.Query.filter(sequence_id == ^seq_a.id)
        |> Ash.read!(authorize?: false)

      assert length(pieces) == 1
    end

    test "removing a sequence not on the spine returns 422", %{
      conn: conn,
      story: story,
      seq_a: seq_a,
      raw_token: raw_token
    } do
      remove_from_spine(story.id, seq_a.id)

      conn =
        conn
        |> auth(raw_token)
        |> post("/api/stories/#{story.id}/sequences/#{seq_a.id}/spine/remove", %{})

      assert json_response(conn, 422)["error"] == "sequence not on spine"
    end
  end

  test "reinstate round-trip: remove then insert at a position lands densely", %{
    story: story,
    seq_a: seq_a,
    raw_token: raw_token
  } do
    build_conn()
    |> auth(raw_token)
    |> post("/api/stories/#{story.id}/sequences/#{seq_a.id}/spine/remove", %{})

    conn =
      build_conn()
      |> auth(raw_token)
      |> post("/api/stories/#{story.id}/sequences/#{seq_a.id}/spine/insert", %{
        "position" => 2
      })

    body = json_response(conn, 201)
    assert body["position"] == 2
    assert positions(story.id) == [1, 2, 3]
    assert Enum.at(spine_order(story.id), 1) == {seq_a.id, 2}
  end
end
