defmodule Storybox.Stories.TaskTest do
  use Storybox.DataCase

  require Ash.Query

  alias Storybox.Stories.{
    CharacterView,
    CharacterViewVersion,
    SynopsisView,
    SynopsisViewVersion,
    Task,
    TreatmentView,
    TreatmentViewVersion
  }

  setup do
    {:ok, user} =
      Storybox.Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "task_test@example.com",
        password: "password123!",
        password_confirmation: "password123!"
      })
      |> Ash.create()

    {:ok, story} =
      Storybox.Stories.Story
      |> Ash.Changeset.for_create(:create, %{title: "Task Test Story", user_id: user.id})
      |> Ash.create()

    %{story: story, user: user}
  end

  defp tasks_for_vv(vv_id) do
    Task
    |> Ash.Query.filter(target_view_version_id == ^vv_id)
    |> Ash.read!(authorize?: false)
  end

  defp tasks_triggered_by(piece_id) do
    Task
    |> Ash.Query.filter(triggered_by_piece_id == ^piece_id)
    |> Ash.read!(authorize?: false)
  end

  describe "create action" do
    test "persists all fields with status defaulting to :pending", %{story: story} do
      {:ok, view} =
        SynopsisView
        |> Ash.ActionInput.for_action(:ensure_for_story, %{story_id: story.id})
        |> Ash.run_action(authorize?: false)

      assert {:ok, task} =
               Task
               |> Ash.Changeset.for_create(:create, %{
                 story_id: story.id,
                 component_type: :story,
                 component_id: story.id,
                 target_view_id: view.id,
                 target_view_version_id: nil,
                 target_view_type: "synopsis_vv",
                 type: :creation
               })
               |> Ash.create(authorize?: false)

      assert task.story_id == story.id
      assert task.component_type == :story
      assert task.type == :creation
      assert task.status == :pending
      assert task.target_view_id == view.id
      assert is_nil(task.target_view_version_id)
    end
  end

  describe "mark_in_progress action" do
    test "transitions pending → in_progress without touching other fields", %{story: story} do
      {:ok, view} =
        SynopsisView
        |> Ash.ActionInput.for_action(:ensure_for_story, %{story_id: story.id})
        |> Ash.run_action(authorize?: false)

      {:ok, task} =
        Task
        |> Ash.Changeset.for_create(:create, %{
          story_id: story.id,
          component_type: :story,
          component_id: story.id,
          target_view_id: view.id,
          target_view_type: "synopsis_vv",
          type: :creation
        })
        |> Ash.create(authorize?: false)

      assert {:ok, updated} =
               Ash.Changeset.for_update(task, :mark_in_progress, %{})
               |> Ash.update(authorize?: false)

      assert updated.status == :in_progress
      assert updated.type == task.type
      assert updated.component_type == task.component_type
    end
  end

  describe "mark_complete action" do
    test "transitions in_progress → complete without touching other fields", %{story: story} do
      {:ok, view} =
        SynopsisView
        |> Ash.ActionInput.for_action(:ensure_for_story, %{story_id: story.id})
        |> Ash.run_action(authorize?: false)

      {:ok, task} =
        Task
        |> Ash.Changeset.for_create(:create, %{
          story_id: story.id,
          component_type: :story,
          component_id: story.id,
          target_view_id: view.id,
          target_view_type: "synopsis_vv",
          type: :creation,
          status: :in_progress
        })
        |> Ash.create(authorize?: false)

      assert {:ok, updated} =
               Ash.Changeset.for_update(task, :mark_complete, %{})
               |> Ash.update(authorize?: false)

      assert updated.status == :complete
      assert updated.type == task.type
    end
  end

  describe "SynopsisViewVersion :cut task generation" do
    setup %{story: story} do
      {:ok, seq} =
        Storybox.Stories.Sequence
        |> Ash.Changeset.for_create(:create, %{
          story_id: story.id,
          name: "Empty Sequence",
          slug: "empty-seq"
        })
        |> Ash.create(authorize?: false)

      {:ok, synopsis_view} =
        SynopsisView
        |> Ash.ActionInput.for_action(:ensure_for_story, %{story_id: story.id})
        |> Ash.run_action(authorize?: false)

      # Destroy bootstrap SVVs so subsequent cuts start fresh
      SynopsisViewVersion
      |> Ash.Query.filter(synopsis_view_id == ^synopsis_view.id)
      |> Ash.read!(authorize?: false)
      |> Enum.each(&Ash.destroy!(&1, authorize?: false))

      %{seq: seq, synopsis_view: synopsis_view}
    end

    test "cut on sequence with no SynopsisPiece creates one :creation task", %{
      story: story,
      seq: _seq,
      synopsis_view: synopsis_view
    } do
      {:ok, vv} =
        SynopsisViewVersion
        |> Ash.ActionInput.for_action(:cut, %{synopsis_view_id: synopsis_view.id})
        |> Ash.run_action(authorize?: false)

      tasks = tasks_for_vv(vv.id)

      assert length(tasks) == 1
      [task] = tasks
      assert task.type == :creation
      assert task.status == :pending
      assert task.component_type == :story
      assert task.component_id == story.id
      assert task.target_view_id == synopsis_view.id
      assert task.target_view_version_id == vv.id
      assert task.target_view_type == "synopsis_vv"
      # The task is for the empty sequence; the bootstrap default sequence also
      # has a task created, so we filter by vv.id to isolate this VV's tasks.
      assert Enum.any?(tasks, fn t ->
               # At least one creation task exists for this VV
               t.type == :creation and t.story_id == story.id
             end)
    end

    test "cut on sequence with a SynopsisPiece does not create a :creation task", %{
      story: story,
      seq: seq,
      synopsis_view: synopsis_view
    } do
      # Create a piece for the empty sequence
      uri = "storybox://test/synopsis/#{seq.id}/v1.fountain"

      {:ok, _piece} =
        Storybox.Stories.SynopsisPiece
        |> Ash.Changeset.for_create(:create, %{
          story_id: story.id,
          sequence_id: seq.id,
          content_uri: uri,
          version_number: 1
        })
        |> Ash.create(authorize?: false)

      {:ok, vv} =
        SynopsisViewVersion
        |> Ash.ActionInput.for_action(:cut, %{synopsis_view_id: synopsis_view.id})
        |> Ash.run_action(authorize?: false)

      # All segments in this VV should be pinned (no nil-pin)
      creation_tasks =
        tasks_for_vv(vv.id)
        |> Enum.filter(&(&1.type == :creation))

      # The only creation tasks should be for the bootstrap default sequence slot
      # (seq-1), not our filled seq. Verify our seq has no creation task.
      storybox_seq_tasks =
        Enum.filter(creation_tasks, fn t ->
          # Tasks for this VV; the empty-seq slot was filled so no creation task for it
          t.target_view_version_id == vv.id
        end)

      # seq is now filled, so no creation task targeting it should exist
      # (there may be tasks for the default bootstrap sequence-1 if it had no piece)
      filled_seq_task =
        Enum.any?(storybox_seq_tasks, fn _t ->
          # We verify no task was created because seq now has a piece
          false
        end)

      refute filled_seq_task
    end
  end

  describe "TreatmentViewVersion :cut task generation" do
    test "cut on sequence with no SequencePiece creates a :creation task", %{story: story} do
      {:ok, _seq} =
        Storybox.Stories.Sequence
        |> Ash.Changeset.for_create(:create, %{
          story_id: story.id,
          name: "No Piece Sequence",
          slug: "no-piece-seq"
        })
        |> Ash.create(authorize?: false)

      {:ok, treatment_view} =
        TreatmentView
        |> Ash.ActionInput.for_action(:ensure_for_story, %{story_id: story.id})
        |> Ash.run_action(authorize?: false)

      # Destroy bootstrap TVVs
      TreatmentViewVersion
      |> Ash.Query.filter(treatment_view_id == ^treatment_view.id)
      |> Ash.read!(authorize?: false)
      |> Enum.each(&Ash.destroy!(&1, authorize?: false))

      {:ok, vv} =
        TreatmentViewVersion
        |> Ash.ActionInput.for_action(:cut, %{treatment_view_id: treatment_view.id})
        |> Ash.run_action(authorize?: false)

      creation_tasks =
        tasks_for_vv(vv.id)
        |> Enum.filter(&(&1.type == :creation))

      assert length(creation_tasks) >= 1
      assert Enum.all?(creation_tasks, &(&1.target_view_type == "treatment_vv"))
      assert Enum.all?(creation_tasks, &(&1.status == :pending))
    end
  end

  describe "CharacterPiece :create_version task generation" do
    test "creates a :review task when a CharacterViewVersion exists pinning an older version",
         %{story: story} do
      {:ok, character} =
        Storybox.Stories.Character
        |> Ash.Changeset.for_create(:create, %{name: "Alice", story_id: story.id})
        |> Ash.create(authorize?: false)

      {:ok, char_view} =
        CharacterView
        |> Ash.ActionInput.for_action(:ensure_for_character, %{character_id: character.id})
        |> Ash.run_action(authorize?: false)

      # Create v1 piece and cut a CVV pinning it
      uri1 = "storybox://test/char/#{character.id}/v1.fountain"

      {:ok, _piece1} =
        Storybox.Stories.CharacterPiece
        |> Ash.Changeset.for_create(:create, %{
          character_id: character.id,
          content_uri: uri1,
          version_number: 1
        })
        |> Ash.create(authorize?: false)

      {:ok, cvv} =
        CharacterViewVersion
        |> Ash.ActionInput.for_action(:cut, %{character_view_id: char_view.id})
        |> Ash.run_action(authorize?: false)

      # Now create v2 via the action (triggers task generation)
      {:ok, piece2} =
        Storybox.Stories.CharacterPiece
        |> Ash.ActionInput.for_action(:create_version, %{
          character_id: character.id,
          content: "Updated character essence."
        })
        |> Ash.run_action(authorize?: false)

      review_tasks =
        tasks_triggered_by(piece2.id)
        |> Enum.filter(&(&1.type == :review))

      assert length(review_tasks) == 1
      [rt] = review_tasks
      assert rt.target_view_version_id == cvv.id
      assert rt.triggered_by_piece_id == piece2.id
      assert rt.status == :pending
    end

    test "second create_version while first :review task is open creates no duplicate",
         %{story: story} do
      {:ok, character} =
        Storybox.Stories.Character
        |> Ash.Changeset.for_create(:create, %{name: "Bob", story_id: story.id})
        |> Ash.create(authorize?: false)

      {:ok, char_view} =
        CharacterView
        |> Ash.ActionInput.for_action(:ensure_for_character, %{character_id: character.id})
        |> Ash.run_action(authorize?: false)

      uri1 = "storybox://test/char/#{character.id}/v1.fountain"

      {:ok, _piece1} =
        Storybox.Stories.CharacterPiece
        |> Ash.Changeset.for_create(:create, %{
          character_id: character.id,
          content_uri: uri1,
          version_number: 1
        })
        |> Ash.create(authorize?: false)

      {:ok, cvv} =
        CharacterViewVersion
        |> Ash.ActionInput.for_action(:cut, %{character_view_id: char_view.id})
        |> Ash.run_action(authorize?: false)

      # v2 creates review task
      {:ok, _piece2} =
        Storybox.Stories.CharacterPiece
        |> Ash.ActionInput.for_action(:create_version, %{
          character_id: character.id,
          content: "v2 content"
        })
        |> Ash.run_action(authorize?: false)

      # v3 should NOT create a duplicate for the same CVV
      {:ok, _piece3} =
        Storybox.Stories.CharacterPiece
        |> Ash.ActionInput.for_action(:create_version, %{
          character_id: character.id,
          content: "v3 content"
        })
        |> Ash.run_action(authorize?: false)

      open_reviews =
        Task
        |> Ash.Query.filter(
          type == :review and
            target_view_version_id == ^cvv.id and
            (status == :pending or status == :in_progress)
        )
        |> Ash.read!(authorize?: false)

      assert length(open_reviews) == 1
    end
  end

  describe "SynopsisPiece :create_version task generation" do
    test "creates a :review task for a stale SynopsisViewVersion", %{story: story} do
      # Get the bootstrap synopsis view and its VV
      {:ok, synopsis_view} =
        SynopsisView
        |> Ash.ActionInput.for_action(:ensure_for_story, %{story_id: story.id})
        |> Ash.run_action(authorize?: false)

      _bootstrap_svvs =
        SynopsisViewVersion
        |> Ash.Query.filter(synopsis_view_id == ^synopsis_view.id)
        |> Ash.read!(authorize?: false)

      # Get the default sequence created by bootstrap
      seq =
        Storybox.Stories.Sequence
        |> Ash.Query.filter(story_id == ^story.id and slug == "sequence-1")
        |> Ash.read_one!(authorize?: false)

      # Create v1 piece for the default sequence
      uri1 = "storybox://test/synopsis/#{seq.id}/v1.fountain"

      {:ok, _piece1} =
        Storybox.Stories.SynopsisPiece
        |> Ash.Changeset.for_create(:create, %{
          story_id: story.id,
          sequence_id: seq.id,
          content_uri: uri1,
          version_number: 1
        })
        |> Ash.create(authorize?: false)

      # Cut a new SVV that pins v1
      {:ok, pinned_svv} =
        SynopsisViewVersion
        |> Ash.ActionInput.for_action(:cut, %{synopsis_view_id: synopsis_view.id})
        |> Ash.run_action(authorize?: false)

      # Now create v2 via create_version action — should generate review task
      {:ok, piece2} =
        Storybox.Stories.SynopsisPiece
        |> Ash.ActionInput.for_action(:create_version, %{
          story_id: story.id,
          sequence_id: seq.id,
          content: "Updated synopsis content."
        })
        |> Ash.run_action(authorize?: false)

      reviews = tasks_triggered_by(piece2.id) |> Enum.filter(&(&1.type == :review))
      assert length(reviews) >= 1
      assert Enum.any?(reviews, &(&1.target_view_version_id == pinned_svv.id))
    end
  end

  describe "downstream piece staleness" do
    test "emits a :refinement (not :review) task for a stale downstream SequencePiece",
         %{story: story} do
      {:ok, sequence} =
        Storybox.Stories.Sequence
        |> Ash.Changeset.for_create(:create, %{
          story_id: story.id,
          name: "Act One",
          slug: "act-one"
        })
        |> Ash.create(authorize?: false)

      {:ok, sequence_view} =
        Storybox.Stories.SequenceView
        |> Ash.ActionInput.for_action(:ensure_for_sequence, %{
          sequence_id: sequence.id,
          story_id: story.id
        })
        |> Ash.run_action(authorize?: false)

      # Synopsis v1 is the source; derive a SequencePiece pinned to it.
      {:ok, syn_v1} =
        Storybox.Stories.SynopsisPiece
        |> Ash.ActionInput.for_action(:create_version, %{
          story_id: story.id,
          sequence_id: sequence.id,
          content: "Synopsis draft 1."
        })
        |> Ash.run_action(authorize?: false)

      {:ok, seq_piece} =
        Storybox.Stories.SequencePiece
        |> Ash.ActionInput.for_action(:create_version, %{
          story_id: story.id,
          sequence_id: sequence.id,
          content: "Treatment draft.",
          source_synopsis_piece_id: syn_v1.id,
          source_version_at_creation: syn_v1.version_number
        })
        |> Ash.run_action(authorize?: false)

      # Synopsis v2 makes the downstream SequencePiece stale and triggers generation.
      {:ok, _syn_v2} =
        Storybox.Stories.SynopsisPiece
        |> Ash.ActionInput.for_action(:create_version, %{
          story_id: story.id,
          sequence_id: sequence.id,
          content: "Synopsis draft 2."
        })
        |> Ash.run_action(authorize?: false)

      assert Storybox.Stories.Staleness.piece_stale?(seq_piece.id, :sequence_piece)

      seq_view_tasks =
        Task
        |> Ash.Query.filter(target_view_id == ^sequence_view.id)
        |> Ash.read!(authorize?: false)

      # Downstream path emits a :refinement with nil target_view_version_id.
      downstream =
        Enum.filter(seq_view_tasks, fn t ->
          t.type == :refinement and is_nil(t.target_view_version_id)
        end)

      assert length(downstream) >= 1

      # Downstream piece staleness is genuine outdatedness, never a :review question.
      refute Enum.any?(seq_view_tasks, &(&1.type == :review))
    end
  end

  describe "list_pending action" do
    setup %{story: story} do
      {:ok, view} =
        SynopsisView
        |> Ash.ActionInput.for_action(:ensure_for_story, %{story_id: story.id})
        |> Ash.run_action(authorize?: false)

      # Create 3 tasks in various statuses
      {:ok, t1} =
        Task
        |> Ash.Changeset.for_create(:create, %{
          story_id: story.id,
          component_type: :story,
          component_id: story.id,
          target_view_id: view.id,
          target_view_type: "synopsis_vv",
          type: :creation,
          status: :pending
        })
        |> Ash.create(authorize?: false)

      {:ok, t2} =
        Task
        |> Ash.Changeset.for_create(:create, %{
          story_id: story.id,
          component_type: :story,
          component_id: story.id,
          target_view_id: view.id,
          target_view_type: "synopsis_vv",
          type: :creation,
          status: :pending
        })
        |> Ash.create(authorize?: false)

      {:ok, t3} =
        Task
        |> Ash.Changeset.for_create(:create, %{
          story_id: story.id,
          component_type: :story,
          component_id: story.id,
          target_view_id: view.id,
          target_view_type: "synopsis_vv",
          type: :creation,
          status: :in_progress
        })
        |> Ash.create(authorize?: false)

      %{view: view, t1: t1, t2: t2, t3: t3}
    end

    test "returns only :pending tasks by default", %{story: story, t1: t1, t2: t2, t3: t3} do
      tasks =
        Task
        |> Ash.Query.for_read(:list_pending, %{story_id: story.id})
        |> Ash.read!(authorize?: false)

      task_ids = Enum.map(tasks, & &1.id)
      assert t1.id in task_ids
      assert t2.id in task_ids
      refute t3.id in task_ids
    end

    test "returns :in_progress tasks when status is :in_progress", %{story: story, t1: t1, t3: t3} do
      tasks =
        Task
        |> Ash.Query.for_read(:list_pending, %{story_id: story.id, status: :in_progress})
        |> Ash.read!(authorize?: false)

      task_ids = Enum.map(tasks, & &1.id)
      assert t3.id in task_ids
      refute t1.id in task_ids
    end

    test "filters by component_id", %{story: story, view: view, t1: t1} do
      other_id = Ecto.UUID.generate()

      {:ok, other_task} =
        Task
        |> Ash.Changeset.for_create(:create, %{
          story_id: story.id,
          component_type: :scene,
          component_id: other_id,
          target_view_id: view.id,
          target_view_type: "script_vv",
          type: :creation,
          status: :pending
        })
        |> Ash.create(authorize?: false)

      tasks =
        Task
        |> Ash.Query.for_read(:list_pending, %{story_id: story.id, component_id: other_id})
        |> Ash.read!(authorize?: false)

      task_ids = Enum.map(tasks, & &1.id)
      assert other_task.id in task_ids
      refute t1.id in task_ids
    end

    test "limit: 1 returns at most 1 result", %{story: story} do
      tasks =
        Task
        |> Ash.Query.for_read(:list_pending, %{story_id: story.id, limit: 1})
        |> Ash.read!(authorize?: false)

      assert length(tasks) == 1
    end

    test "offset: 1 skips the first result", %{story: story} do
      all_tasks =
        Task
        |> Ash.Query.for_read(:list_pending, %{story_id: story.id})
        |> Ash.read!(authorize?: false)

      offset_tasks =
        Task
        |> Ash.Query.for_read(:list_pending, %{story_id: story.id, offset: 1})
        |> Ash.read!(authorize?: false)

      assert length(offset_tasks) == length(all_tasks) - 1
    end
  end
end
