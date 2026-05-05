defmodule Storybox.Stories.StalenessTest do
  use Storybox.DataCase

  require Ash.Query

  alias Storybox.Stories.{
    Scene,
    ScriptPiece,
    ScriptView,
    ScriptViewVersion,
    Segment,
    SequencePiece,
    Staleness,
    Story,
    SynopsisPiece
  }

  setup do
    {:ok, user} =
      Storybox.Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "staleness_test@example.com",
        password: "password123!",
        password_confirmation: "password123!"
      })
      |> Ash.create()

    {:ok, story} =
      Story
      |> Ash.Changeset.for_create(:create, %{title: "Staleness Story", user_id: user.id})
      |> Ash.create()

    {:ok, scene} =
      Scene
      |> Ash.Changeset.for_create(:create, %{title: "Cottage", story_id: story.id})
      |> Ash.create()

    {:ok, script_view} =
      ScriptView
      |> Ash.Changeset.for_create(:create, %{scene_id: scene.id})
      |> Ash.create()

    {:ok, sp1} =
      ScriptPiece
      |> Ash.ActionInput.for_action(:create_version, %{
        scene_id: scene.id,
        content: "INT. COTTAGE - DAY\n\nFirst draft."
      })
      |> Ash.run_action()

    {:ok, vv1} =
      ScriptViewVersion
      |> Ash.ActionInput.for_action(:cut, %{
        script_view_id: script_view.id,
        script_piece_id: sp1.id
      })
      |> Ash.run_action()

    %{
      story: story,
      scene: scene,
      script_view: script_view,
      sp1: sp1,
      vv1: vv1
    }
  end

  describe "view_version_stale?/2" do
    test "returns false for a fresh VV pinned to the latest piece", %{vv1: vv1} do
      refute Staleness.view_version_stale?(vv1.id, :script_vv)
    end

    test "returns true once a newer ScriptPiece version exists", %{
      vv1: vv1,
      scene: scene
    } do
      {:ok, _sp2} =
        ScriptPiece
        |> Ash.ActionInput.for_action(:create_version, %{
          scene_id: scene.id,
          content: "INT. COTTAGE - DAY\n\nRevised draft."
        })
        |> Ash.run_action()

      assert Staleness.view_version_stale?(vv1.id, :script_vv)
    end
  end

  describe "view_version_stale_segments/2" do
    test "returns the stale Segment when a newer piece exists", %{
      vv1: vv1,
      scene: scene
    } do
      {:ok, _sp2} =
        ScriptPiece
        |> Ash.ActionInput.for_action(:create_version, %{
          scene_id: scene.id,
          content: "INT. COTTAGE - DAY\n\nRevised draft."
        })
        |> Ash.run_action()

      [stale_seg] = Staleness.view_version_stale_segments(vv1.id, :script_vv)

      [expected_seg] =
        Segment
        |> Ash.Query.filter(view_version_id == ^vv1.id)
        |> Ash.read!(authorize?: false)

      assert stale_seg.id == expected_seg.id
    end

    test "returns an empty list when nothing is stale", %{vv1: vv1} do
      assert Staleness.view_version_stale_segments(vv1.id, :script_vv) == []
    end
  end

  describe "piece_stale?/2" do
    test "returns true for a SequencePiece whose source SynopsisPiece has a newer version", %{
      story: story
    } do
      {:ok, sequence} =
        Storybox.Stories.Sequence
        |> Ash.Changeset.for_create(:create, %{
          story_id: story.id,
          name: "Act One",
          slug: "act-one"
        })
        |> Ash.create()

      {:ok, syn_v1} =
        SynopsisPiece
        |> Ash.ActionInput.for_action(:create_version, %{
          story_id: story.id,
          sequence_id: sequence.id,
          content: "Synopsis draft 1."
        })
        |> Ash.run_action()

      {:ok, seq_piece} =
        SequencePiece
        |> Ash.ActionInput.for_action(:create_version, %{
          story_id: story.id,
          sequence_id: sequence.id,
          content: "Treatment draft.",
          source_synopsis_piece_id: syn_v1.id,
          source_version_at_creation: syn_v1.version_number
        })
        |> Ash.run_action()

      refute Staleness.piece_stale?(seq_piece.id, :sequence_piece)

      {:ok, _syn_v2} =
        SynopsisPiece
        |> Ash.ActionInput.for_action(:create_version, %{
          story_id: story.id,
          sequence_id: sequence.id,
          content: "Synopsis draft 2."
        })
        |> Ash.run_action()

      assert Staleness.piece_stale?(seq_piece.id, :sequence_piece)
    end

    test "returns false for a SynopsisPiece (no provenance type)", %{story: story} do
      {:ok, sequence} =
        Storybox.Stories.Sequence
        |> Ash.Changeset.for_create(:create, %{
          story_id: story.id,
          name: "Act Two",
          slug: "act-two"
        })
        |> Ash.create()

      {:ok, syn} =
        SynopsisPiece
        |> Ash.ActionInput.for_action(:create_version, %{
          story_id: story.id,
          sequence_id: sequence.id,
          content: "Synopsis only."
        })
        |> Ash.run_action()

      refute Staleness.piece_stale?(syn.id, :synopsis_piece)
    end

    test "returns false for a ScriptPiece with no source_sequence_piece_id", %{sp1: sp1} do
      refute Staleness.piece_stale?(sp1.id, :script_piece)
    end

    test "returns false for :character_piece and :world_piece (no provenance)" do
      bogus_id = Ecto.UUID.generate()
      refute Staleness.piece_stale?(bogus_id, :character_piece)
      refute Staleness.piece_stale?(bogus_id, :world_piece)
    end
  end
end
