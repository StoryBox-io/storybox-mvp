defmodule Storybox.Stories.StorySpineTest do
  use Storybox.DataCase

  alias Storybox.Stories.{Sequence, StorySpine, StorySpineEntry}

  require Ash.Query

  setup do
    {:ok, user} =
      Storybox.Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "spine_test@example.com",
        password: "password123!",
        password_confirmation: "password123!"
      })
      |> Ash.create()

    {:ok, story} =
      Storybox.Stories.Story
      |> Ash.Changeset.for_create(:create, %{title: "Test Story", user_id: user.id})
      |> Ash.create()

    %{story: story}
  end

  defp create_sequence(story_id, slug) do
    {:ok, seq} =
      Sequence
      |> Ash.Changeset.for_create(:create, %{name: slug, slug: slug, story_id: story_id})
      |> Ash.create()

    seq
  end

  defp spine_for(story_id) do
    {:ok, spine} =
      StorySpine
      |> Ash.ActionInput.for_action(:ensure_for_story, %{story_id: story_id})
      |> Ash.run_action()

    spine
  end

  defp entries_for(spine_id) do
    StorySpineEntry
    |> Ash.Query.filter(story_spine_id == ^spine_id)
    |> Ash.Query.sort(:position)
    |> Ash.read!(authorize?: false)
  end

  describe "bootstrap" do
    test "story bootstrap creates a spine with the default sequence as its only entry", %{
      story: story
    } do
      spine =
        StorySpine
        |> Ash.Query.filter(story_id == ^story.id)
        |> Ash.read_one!(authorize?: false)

      assert spine
      assert spine.story_id == story.id

      default_seq =
        Sequence
        |> Ash.Query.filter(story_id == ^story.id)
        |> Ash.read_one!(authorize?: false)

      entries = entries_for(spine.id)
      assert [entry] = entries
      assert entry.sequence_id == default_seq.id
      assert entry.position == 1
    end
  end

  describe "ensure_for_story" do
    test "is idempotent — second call returns the same spine", %{story: story} do
      spine1 = spine_for(story.id)
      spine2 = spine_for(story.id)
      assert spine1.id == spine2.id

      all =
        StorySpine
        |> Ash.Query.filter(story_id == ^story.id)
        |> Ash.read!(authorize?: false)

      assert length(all) == 1
    end
  end

  describe "add_entry" do
    test "inserts an entry at max_position + 1", %{story: story} do
      spine = spine_for(story.id)
      # bootstrap already added the default sequence at position 1
      seq = create_sequence(story.id, "seq-b")

      {:ok, entry} =
        StorySpine
        |> Ash.ActionInput.for_action(:add_entry, %{
          story_spine_id: spine.id,
          sequence_id: seq.id
        })
        |> Ash.run_action()

      assert entry.sequence_id == seq.id
      assert entry.position == 2
    end

    test "accepts an explicit position", %{story: story} do
      spine = spine_for(story.id)
      seq = create_sequence(story.id, "seq-b")

      {:ok, entry} =
        StorySpine
        |> Ash.ActionInput.for_action(:add_entry, %{
          story_spine_id: spine.id,
          sequence_id: seq.id,
          position: 5
        })
        |> Ash.run_action()

      assert entry.position == 5
    end

    test "rejects a duplicate sequence on the same spine", %{story: story} do
      spine = spine_for(story.id)

      default_entry =
        StorySpineEntry
        |> Ash.Query.filter(story_spine_id == ^spine.id)
        |> Ash.read_one!(authorize?: false)

      assert {:error, _} =
               StorySpine
               |> Ash.ActionInput.for_action(:add_entry, %{
                 story_spine_id: spine.id,
                 sequence_id: default_entry.sequence_id
               })
               |> Ash.run_action()
    end
  end

  describe "remove_entry" do
    test "deletes the entry and repacks remaining positions to 1..n", %{story: story} do
      spine = spine_for(story.id)
      seq_b = create_sequence(story.id, "seq-b")
      seq_c = create_sequence(story.id, "seq-c")

      add(spine.id, seq_b.id)
      add(spine.id, seq_c.id)

      # spine now: [default(1), seq_b(2), seq_c(3)] — remove the middle one
      {:ok, _} =
        StorySpine
        |> Ash.ActionInput.for_action(:remove_entry, %{
          story_spine_id: spine.id,
          sequence_id: seq_b.id
        })
        |> Ash.run_action()

      entries = entries_for(spine.id)
      assert length(entries) == 2
      assert Enum.map(entries, & &1.position) == [1, 2]
      refute Enum.any?(entries, &(&1.sequence_id == seq_b.id))
      assert List.last(entries).sequence_id == seq_c.id
    end
  end

  describe "reorder_entry" do
    test "moves the entry and shifts others without gaps", %{story: story} do
      spine = spine_for(story.id)
      seq_b = create_sequence(story.id, "seq-b")
      seq_c = create_sequence(story.id, "seq-c")

      default_entry =
        StorySpineEntry
        |> Ash.Query.filter(story_spine_id == ^spine.id)
        |> Ash.read_one!(authorize?: false)

      default_seq_id = default_entry.sequence_id

      add(spine.id, seq_b.id)
      add(spine.id, seq_c.id)

      # [default(1), seq_b(2), seq_c(3)] — move seq_c to position 1
      {:ok, _} =
        StorySpine
        |> Ash.ActionInput.for_action(:reorder_entry, %{
          story_spine_id: spine.id,
          sequence_id: seq_c.id,
          new_position: 1
        })
        |> Ash.run_action()

      ordered =
        entries_for(spine.id)
        |> Enum.map(& &1.sequence_id)

      assert ordered == [seq_c.id, default_seq_id, seq_b.id]
      assert Enum.map(entries_for(spine.id), & &1.position) == [1, 2, 3]
    end
  end

  defp add(spine_id, sequence_id) do
    {:ok, _} =
      StorySpine
      |> Ash.ActionInput.for_action(:add_entry, %{
        story_spine_id: spine_id,
        sequence_id: sequence_id
      })
      |> Ash.run_action()
  end
end
