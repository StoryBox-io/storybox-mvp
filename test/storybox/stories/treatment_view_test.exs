defmodule Storybox.Stories.TreatmentViewTest do
  use Storybox.DataCase

  require Ash.Query

  # Shared seed data:
  #
  #   User → Story: Little Witch
  #            ├─ TreatmentView (created by ensure_for_story)
  #            ├─ Sequence: prologue  → SequencePiece v1 (muted), v2 (latest)
  #            ├─ Sequence: forest    → SequencePiece v1 (latest)
  #            └─ Sequence: capital   → (no SequencePiece)
  #
  # Sequences are inserted in prologue → forest → capital order so that
  # inserted_at ordering is deterministic for the first-cut fallback.

  setup do
    {:ok, user} =
      Storybox.Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "test@example.com",
        password: "Password1!",
        password_confirmation: "Password1!"
      })
      |> Ash.create()

    {:ok, story} =
      Storybox.Stories.Story
      |> Ash.Changeset.for_create(:create, %{title: "Little Witch", user_id: user.id})
      |> Ash.create()

    {:ok, seq1} =
      Storybox.Stories.Sequence
      |> Ash.Changeset.for_create(:create, %{
        name: "prologue",
        slug: "prologue",
        story_id: story.id
      })
      |> Ash.create()

    {:ok, seq2} =
      Storybox.Stories.Sequence
      |> Ash.Changeset.for_create(:create, %{name: "forest", slug: "forest", story_id: story.id})
      |> Ash.create()

    {:ok, seq3} =
      Storybox.Stories.Sequence
      |> Ash.Changeset.for_create(:create, %{name: "capital", slug: "capital", story_id: story.id})
      |> Ash.create()

    {:ok, p1a} =
      Storybox.Stories.SequencePiece
      |> Ash.Changeset.for_create(:create, %{
        story_id: story.id,
        sequence_id: seq1.id,
        content_uri: "storybox://test/prologue/v1",
        version_number: 1
      })
      |> Ash.create()

    {:ok, p1b} =
      Storybox.Stories.SequencePiece
      |> Ash.Changeset.for_create(:create, %{
        story_id: story.id,
        sequence_id: seq1.id,
        content_uri: "storybox://test/prologue/v2",
        version_number: 2
      })
      |> Ash.create()

    {:ok, p2} =
      Storybox.Stories.SequencePiece
      |> Ash.Changeset.for_create(:create, %{
        story_id: story.id,
        sequence_id: seq2.id,
        content_uri: "storybox://test/forest/v1",
        version_number: 1
      })
      |> Ash.create()

    %{
      story: story,
      seq1: seq1,
      seq2: seq2,
      seq3: seq3,
      p1a: p1a,
      p1b: p1b,
      p2: p2
    }
  end

  describe "ensure_for_story" do
    test "creates a TreatmentView for the story", %{story: story} do
      assert {:ok, tv} =
               Storybox.Stories.TreatmentView
               |> Ash.ActionInput.for_action(:ensure_for_story, %{story_id: story.id})
               |> Ash.run_action()

      assert tv.story_id == story.id
    end

    test "is idempotent — second call returns the same record", %{story: story} do
      {:ok, tv1} =
        Storybox.Stories.TreatmentView
        |> Ash.ActionInput.for_action(:ensure_for_story, %{story_id: story.id})
        |> Ash.run_action()

      {:ok, tv2} =
        Storybox.Stories.TreatmentView
        |> Ash.ActionInput.for_action(:ensure_for_story, %{story_id: story.id})
        |> Ash.run_action()

      assert tv1.id == tv2.id

      all =
        Storybox.Stories.TreatmentView |> Ash.Query.filter(story_id == ^story.id) |> Ash.read!()

      assert length(all) == 1
    end
  end

  describe "cut" do
    setup %{story: story} do
      {:ok, tv} =
        Storybox.Stories.TreatmentView
        |> Ash.ActionInput.for_action(:ensure_for_story, %{story_id: story.id})
        |> Ash.run_action()

      # Destroy the bootstrap TVV so cut tests exercise first-cut semantics
      # (falls back to all sequences by inserted_at, producing 4 segments: the
      # bootstrap "Sequence 1" plus the 3 test sequences added in setup).
      Storybox.Stories.TreatmentViewVersion
      |> Ash.Query.filter(treatment_view_id == ^tv.id)
      |> Ash.read!(authorize?: false)
      |> Enum.each(&Ash.destroy!(&1, authorize?: false))

      %{tv: tv}
    end

    test "creates a TreatmentViewVersion with version_number 1", %{tv: tv} do
      assert {:ok, vv} =
               Storybox.Stories.TreatmentViewVersion
               |> Ash.ActionInput.for_action(:cut, %{treatment_view_id: tv.id})
               |> Ash.run_action()

      assert vv.treatment_view_id == tv.id
      assert vv.version_number == 1
    end

    test "creates exactly 4 Segments — one per Sequence", %{tv: tv} do
      {:ok, vv} =
        Storybox.Stories.TreatmentViewVersion
        |> Ash.ActionInput.for_action(:cut, %{treatment_view_id: tv.id})
        |> Ash.run_action()

      segments =
        Storybox.Stories.Segment
        |> Ash.Query.filter(view_version_id == ^vv.id and view_version_type == :treatment_vv)
        |> Ash.read!()

      assert length(segments) == 4
    end

    test "prologue Segment pins prologue-v2", %{tv: tv, seq1: seq1, p1b: p1b} do
      {:ok, vv} =
        Storybox.Stories.TreatmentViewVersion
        |> Ash.ActionInput.for_action(:cut, %{treatment_view_id: tv.id})
        |> Ash.run_action()

      [seg] =
        Storybox.Stories.Segment
        |> Ash.Query.filter(
          view_version_id == ^vv.id and
            view_version_type == :treatment_vv and
            sequence_id == ^seq1.id
        )
        |> Ash.read!()

      assert seg.pin_id == p1b.id
      assert seg.pin_type == :sequence_piece
      assert seg.pin_version_at_creation == 2
      assert seg.sequence_id == seq1.id
    end

    test "forest Segment pins forest-v1", %{tv: tv, seq2: seq2, p2: p2} do
      {:ok, vv} =
        Storybox.Stories.TreatmentViewVersion
        |> Ash.ActionInput.for_action(:cut, %{treatment_view_id: tv.id})
        |> Ash.run_action()

      [seg] =
        Storybox.Stories.Segment
        |> Ash.Query.filter(
          view_version_id == ^vv.id and
            view_version_type == :treatment_vv and
            sequence_id == ^seq2.id
        )
        |> Ash.read!()

      assert seg.pin_id == p2.id
      assert seg.pin_type == :sequence_piece
      assert seg.pin_version_at_creation == 1
      assert seg.sequence_id == seq2.id
    end

    test "capital Segment is unresolvable", %{tv: tv, seq3: seq3} do
      {:ok, vv} =
        Storybox.Stories.TreatmentViewVersion
        |> Ash.ActionInput.for_action(:cut, %{treatment_view_id: tv.id})
        |> Ash.run_action()

      [seg] =
        Storybox.Stories.Segment
        |> Ash.Query.filter(
          view_version_id == ^vv.id and
            view_version_type == :treatment_vv and
            sequence_id == ^seq3.id
        )
        |> Ash.read!()

      assert is_nil(seg.pin_id)
      assert is_nil(seg.pin_type)
      assert is_nil(seg.pin_version_at_creation)
      assert seg.sequence_id == seq3.id
    end

    test "v1 pins are unchanged after cutting v2 with a newer SequencePiece",
         %{story: story, tv: tv, seq1: seq1, p1b: p1b} do
      {:ok, vv1} =
        Storybox.Stories.TreatmentViewVersion
        |> Ash.ActionInput.for_action(:cut, %{treatment_view_id: tv.id})
        |> Ash.run_action()

      {:ok, _p1c} =
        Storybox.Stories.SequencePiece
        |> Ash.Changeset.for_create(:create, %{
          story_id: story.id,
          sequence_id: seq1.id,
          content_uri: "storybox://test/prologue/v3",
          version_number: 3
        })
        |> Ash.create()

      {:ok, vv2} =
        Storybox.Stories.TreatmentViewVersion
        |> Ash.ActionInput.for_action(:cut, %{treatment_view_id: tv.id})
        |> Ash.run_action()

      assert vv2.version_number == 2

      [v1_seg] =
        Storybox.Stories.Segment
        |> Ash.Query.filter(
          view_version_id == ^vv1.id and
            view_version_type == :treatment_vv and
            sequence_id == ^seq1.id
        )
        |> Ash.read!()

      [v2_seg] =
        Storybox.Stories.Segment
        |> Ash.Query.filter(
          view_version_id == ^vv2.id and
            view_version_type == :treatment_vv and
            sequence_id == ^seq1.id
        )
        |> Ash.read!()

      assert v1_seg.pin_id == p1b.id
      assert v1_seg.pin_version_at_creation == 2

      assert v2_seg.pin_version_at_creation == 3
    end

    test "Segment.resolve_pin returns {:resolved, %SequencePiece{}} for a pinned Segment",
         %{tv: tv, seq1: seq1} do
      {:ok, vv} =
        Storybox.Stories.TreatmentViewVersion
        |> Ash.ActionInput.for_action(:cut, %{treatment_view_id: tv.id})
        |> Ash.run_action()

      [seg] =
        Storybox.Stories.Segment
        |> Ash.Query.filter(
          view_version_id == ^vv.id and
            view_version_type == :treatment_vv and
            sequence_id == ^seq1.id
        )
        |> Ash.read!()

      assert {:resolved, %Storybox.Stories.SequencePiece{}} =
               Storybox.Stories.Segment.resolve_pin(seg)
    end

    test "Segment.pin_target_latest_version returns 3 after prologue-v3 is created",
         %{story: story, tv: tv, seq1: seq1} do
      {:ok, vv} =
        Storybox.Stories.TreatmentViewVersion
        |> Ash.ActionInput.for_action(:cut, %{treatment_view_id: tv.id})
        |> Ash.run_action()

      {:ok, _p1c} =
        Storybox.Stories.SequencePiece
        |> Ash.Changeset.for_create(:create, %{
          story_id: story.id,
          sequence_id: seq1.id,
          content_uri: "storybox://test/prologue/v3",
          version_number: 3
        })
        |> Ash.create()

      [seg] =
        Storybox.Stories.Segment
        |> Ash.Query.filter(
          view_version_id == ^vv.id and
            view_version_type == :treatment_vv and
            sequence_id == ^seq1.id
        )
        |> Ash.read!()

      assert Storybox.Stories.Segment.pin_target_latest_version(seg) == 3
    end
  end
end
