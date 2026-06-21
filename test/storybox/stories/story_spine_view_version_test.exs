defmodule Storybox.Stories.StorySpineViewVersionTest do
  use Storybox.DataCase

  alias Storybox.Stories.{Sequence, StorySpine, StorySpineViewVersion, StorySpineVvEntry}

  require Ash.Query

  setup do
    {:ok, user} =
      Storybox.Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "spine_vv_test@example.com",
        password: "password123!",
        password_confirmation: "password123!"
      })
      |> Ash.create()

    {:ok, story} =
      Storybox.Stories.Story
      |> Ash.Changeset.for_create(:create, %{title: "Test Story", user_id: user.id})
      |> Ash.create()

    spine =
      StorySpine
      |> Ash.Query.filter(story_id == ^story.id)
      |> Ash.read_one!(authorize?: false)

    seq_b = create_sequence(story.id, "seq-b")
    seq_c = create_sequence(story.id, "seq-c")
    add(spine.id, seq_b.id)
    add(spine.id, seq_c.id)

    %{story: story, spine: spine, seq_b: seq_b, seq_c: seq_c}
  end

  defp create_sequence(story_id, slug) do
    {:ok, seq} =
      Sequence
      |> Ash.Changeset.for_create(:create, %{name: slug, slug: slug, story_id: story_id})
      |> Ash.create()

    seq
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

  defp cut(spine_id) do
    {:ok, vv} =
      StorySpineViewVersion
      |> Ash.ActionInput.for_action(:cut, %{story_spine_id: spine_id})
      |> Ash.run_action()

    vv
  end

  defp vv_entries(vv_id) do
    StorySpineVvEntry
    |> Ash.Query.filter(story_spine_view_version_id == ^vv_id)
    |> Ash.Query.sort(:position)
    |> Ash.read!(authorize?: false)
  end

  describe "cut" do
    test "first cut is version 1 and copies live entries in position order", %{
      spine: spine,
      seq_b: seq_b,
      seq_c: seq_c
    } do
      live =
        Storybox.Stories.StorySpineEntry
        |> Ash.Query.filter(story_spine_id == ^spine.id)
        |> Ash.Query.sort(:position)
        |> Ash.read!(authorize?: false)

      vv = cut(spine.id)

      assert vv.version_number == 1
      assert vv.story_spine_id == spine.id

      entries = vv_entries(vv.id)
      assert length(entries) == length(live)
      assert Enum.map(entries, & &1.position) == Enum.map(live, & &1.position)
      assert Enum.map(entries, & &1.sequence_id) == Enum.map(live, & &1.sequence_id)

      # the two added sequences are present in the snapshot
      assert seq_b.id in Enum.map(entries, & &1.sequence_id)
      assert seq_c.id in Enum.map(entries, & &1.sequence_id)
    end

    test "second cut is version 2", %{spine: spine} do
      _vv1 = cut(spine.id)
      vv2 = cut(spine.id)
      assert vv2.version_number == 2
    end

    test "live edits after a cut do not alter the snapshot's entries", %{
      spine: spine,
      seq_b: seq_b
    } do
      vv = cut(spine.id)
      snapshot_before = Enum.map(vv_entries(vv.id), &{&1.sequence_id, &1.position})

      # Mutate the live order after the cut: remove a sequence, add a new one.
      {:ok, _} =
        StorySpine
        |> Ash.ActionInput.for_action(:remove_entry, %{
          story_spine_id: spine.id,
          sequence_id: seq_b.id
        })
        |> Ash.run_action()

      seq_d = create_sequence(spine.story_id, "seq-d")
      add(spine.id, seq_d.id)

      snapshot_after = Enum.map(vv_entries(vv.id), &{&1.sequence_id, &1.position})
      assert snapshot_after == snapshot_before
    end
  end
end
