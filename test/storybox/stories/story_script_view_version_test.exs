defmodule Storybox.Stories.StoryScriptViewVersionTest do
  use Storybox.DataCase

  alias Storybox.Stories.{
    Segment,
    SequenceView,
    SequenceViewVersion,
    StorySpine,
    StoryScriptView,
    StoryScriptViewVersion
  }

  require Ash.Query

  # Setup creates:
  #   User → Story (lazy bootstrap: TreatmentView, SynopsisView, empty StorySpine)
  #   seq_a, seq_b, seq_c — each registers a StorySpine entry on create, so the
  #     live spine order is [seq_a, seq_b, seq_c]
  #   SequenceViews for all three; SequenceViewVersions for seq_a and seq_b only
  #     (seq_c is left unresolvable)
  #   StoryScriptView for the story

  setup do
    {:ok, user} =
      Storybox.Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "ssvv_test@example.com",
        password: "password123!",
        password_confirmation: "password123!"
      })
      |> Ash.create()

    {:ok, story} =
      Storybox.Stories.Story
      |> Ash.Changeset.for_create(:create, %{title: "Test Story", user_id: user.id})
      |> Ash.create()

    {:ok, seq_a} =
      Storybox.Stories.Sequence
      |> Ash.Changeset.for_create(:create, %{name: "seq_a", slug: "seq-a", story_id: story.id})
      |> Ash.create()

    {:ok, seq_b} =
      Storybox.Stories.Sequence
      |> Ash.Changeset.for_create(:create, %{name: "seq_b", slug: "seq-b", story_id: story.id})
      |> Ash.create()

    {:ok, seq_c} =
      Storybox.Stories.Sequence
      |> Ash.Changeset.for_create(:create, %{name: "seq_c", slug: "seq-c", story_id: story.id})
      |> Ash.create()

    {:ok, sv_a} =
      SequenceView
      |> Ash.ActionInput.for_action(:ensure_for_sequence, %{
        sequence_id: seq_a.id,
        story_id: story.id
      })
      |> Ash.run_action()

    {:ok, sv_b} =
      SequenceView
      |> Ash.ActionInput.for_action(:ensure_for_sequence, %{
        sequence_id: seq_b.id,
        story_id: story.id
      })
      |> Ash.run_action()

    {:ok, _sv_c} =
      SequenceView
      |> Ash.ActionInput.for_action(:ensure_for_sequence, %{
        sequence_id: seq_c.id,
        story_id: story.id
      })
      |> Ash.run_action()

    # seq_a has a SequenceViewVersion (resolvable)
    {:ok, svv_a} =
      SequenceViewVersion
      |> Ash.ActionInput.for_action(:cut, %{
        sequence_view_id: sv_a.id,
        segments: []
      })
      |> Ash.run_action()

    # seq_b has a SequenceViewVersion (resolvable)
    {:ok, svv_b} =
      SequenceViewVersion
      |> Ash.ActionInput.for_action(:cut, %{
        sequence_view_id: sv_b.id,
        segments: []
      })
      |> Ash.run_action()

    # seq_c has NO SequenceViewVersion (unresolvable)

    {:ok, story_script_view} =
      StoryScriptView
      |> Ash.ActionInput.for_action(:ensure_for_story, %{story_id: story.id})
      |> Ash.run_action()

    %{
      story: story,
      seq_a: seq_a,
      seq_b: seq_b,
      seq_c: seq_c,
      svv_a: svv_a,
      svv_b: svv_b,
      story_script_view: story_script_view
    }
  end

  describe "cut" do
    test "first cut creates a StoryScriptViewVersion with version_number 1", %{
      story_script_view: ssv
    } do
      assert {:ok, vv} =
               StoryScriptViewVersion
               |> Ash.ActionInput.for_action(:cut, %{story_script_view_id: ssv.id})
               |> Ash.run_action()

      assert vv.version_number == 1
      assert vv.story_script_view_id == ssv.id
    end

    test "an empty spine produces a StoryScriptViewVersion with no segments", %{story: story} do
      {:ok, user2} =
        Storybox.Accounts.User
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: "ssvv_empty@example.com",
          password: "password123!",
          password_confirmation: "password123!"
        })
        |> Ash.create()

      {:ok, empty_story} =
        Storybox.Stories.Story
        |> Ash.Changeset.for_create(:create, %{title: "Empty", user_id: user2.id})
        |> Ash.create()

      {:ok, ssv} =
        StoryScriptView
        |> Ash.ActionInput.for_action(:ensure_for_story, %{story_id: empty_story.id})
        |> Ash.run_action()

      {:ok, vv} =
        StoryScriptViewVersion
        |> Ash.ActionInput.for_action(:cut, %{story_script_view_id: ssv.id})
        |> Ash.run_action()

      segments =
        Segment
        |> Ash.Query.filter(view_version_id == ^vv.id)
        |> Ash.read!(authorize?: false)

      assert segments == []
      _ = story
    end

    test "Segments have view_version_type :story_script_vv and are keyed by sequence_id", %{
      story_script_view: ssv,
      seq_a: seq_a,
      seq_b: seq_b,
      seq_c: seq_c
    } do
      {:ok, vv} =
        StoryScriptViewVersion
        |> Ash.ActionInput.for_action(:cut, %{story_script_view_id: ssv.id})
        |> Ash.run_action()

      segments =
        Segment
        |> Ash.Query.filter(view_version_id == ^vv.id)
        |> Ash.Query.sort(:position)
        |> Ash.read!(authorize?: false)

      assert length(segments) == 3
      assert Enum.all?(segments, &(&1.view_version_type == :story_script_vv))

      # Order-free segments carry their sequence_id (spine order [a, b, c]).
      assert Enum.map(segments, & &1.sequence_id) == [seq_a.id, seq_b.id, seq_c.id]
    end

    test "Segments pin SequenceViewVersions in the live spine order, nil-pin where unresolvable",
         %{
           story_script_view: ssv,
           seq_a: seq_a,
           seq_b: seq_b,
           seq_c: seq_c,
           svv_a: svv_a,
           svv_b: svv_b
         } do
      {:ok, vv} =
        StoryScriptViewVersion
        |> Ash.ActionInput.for_action(:cut, %{story_script_view_id: ssv.id})
        |> Ash.run_action()

      # Spine order: [seq_a, seq_b, seq_c] — positions 1, 2, 3
      [s1, s2, s3] =
        Segment
        |> Ash.Query.filter(view_version_id == ^vv.id)
        |> Ash.Query.sort(:position)
        |> Ash.read!(authorize?: false)

      # position 1 = seq_a (has svv_a)
      assert s1.sequence_id == seq_a.id
      assert s1.pin_id == svv_a.id
      assert s1.pin_type == :sequence_vv
      assert s1.pin_version_at_creation == svv_a.version_number

      # position 2 = seq_b (has svv_b)
      assert s2.sequence_id == seq_b.id
      assert s2.pin_id == svv_b.id
      assert s2.pin_type == :sequence_vv
      assert s2.pin_version_at_creation == svv_b.version_number

      # position 3 = seq_c (no SVV → unresolvable nil-pin, still keyed by sequence)
      assert s3.sequence_id == seq_c.id
      assert is_nil(s3.pin_id)
      assert is_nil(s3.pin_type)
      assert is_nil(s3.pin_version_at_creation)
    end

    test "second cut produces version_number 2; first VV's Segments unchanged", %{
      story_script_view: ssv,
      svv_a: svv_a,
      svv_b: svv_b
    } do
      {:ok, vv1} =
        StoryScriptViewVersion
        |> Ash.ActionInput.for_action(:cut, %{story_script_view_id: ssv.id})
        |> Ash.run_action()

      {:ok, vv2} =
        StoryScriptViewVersion
        |> Ash.ActionInput.for_action(:cut, %{story_script_view_id: ssv.id})
        |> Ash.run_action()

      assert vv2.version_number == 2

      v1_pin_ids =
        Segment
        |> Ash.Query.filter(view_version_id == ^vv1.id)
        |> Ash.Query.sort(:position)
        |> Ash.read!(authorize?: false)
        |> Enum.map(& &1.pin_id)

      # position 1 = seq_a, position 2 = seq_b, position 3 = seq_c (unresolvable = nil)
      assert v1_pin_ids == [svv_a.id, svv_b.id, nil]
    end

    test "Segment.resolve_pin/1 returns {:resolved, %SequenceViewVersion{}} for a :sequence_vv Segment",
         %{story_script_view: ssv, svv_a: svv_a} do
      {:ok, vv} =
        StoryScriptViewVersion
        |> Ash.ActionInput.for_action(:cut, %{story_script_view_id: ssv.id})
        |> Ash.run_action()

      # position 1 = seq_a = svv_a (resolvable)
      pinned_seg =
        Segment
        |> Ash.Query.filter(view_version_id == ^vv.id and not is_nil(pin_id))
        |> Ash.Query.sort(:position)
        |> Ash.read!(authorize?: false)
        |> List.first()

      assert {:resolved, %SequenceViewVersion{id: id}} = Segment.resolve_pin(pinned_seg)
      assert id == svv_a.id
    end

    test "a live spine reorder is reflected in a new StoryScriptVV cut", %{
      story: story,
      story_script_view: ssv,
      seq_a: seq_a,
      seq_b: seq_b,
      seq_c: seq_c,
      svv_a: svv_a,
      svv_b: svv_b
    } do
      spine =
        StorySpine
        |> Ash.Query.filter(story_id == ^story.id)
        |> Ash.read_one!(authorize?: false)

      # Reorder spine from [seq_a, seq_b, seq_c] to [seq_b, seq_c, seq_a].
      StorySpine
      |> Ash.ActionInput.for_action(:reorder_entry, %{
        story_spine_id: spine.id,
        sequence_id: seq_b.id,
        new_position: 1
      })
      |> Ash.run_action!(authorize?: false)

      StorySpine
      |> Ash.ActionInput.for_action(:reorder_entry, %{
        story_spine_id: spine.id,
        sequence_id: seq_c.id,
        new_position: 2
      })
      |> Ash.run_action!(authorize?: false)

      {:ok, vv} =
        StoryScriptViewVersion
        |> Ash.ActionInput.for_action(:cut, %{story_script_view_id: ssv.id})
        |> Ash.run_action()

      [s1, s2, s3] =
        Segment
        |> Ash.Query.filter(view_version_id == ^vv.id)
        |> Ash.Query.sort(:position)
        |> Ash.read!(authorize?: false)

      # position 1 = seq_b (has svv_b)
      assert s1.sequence_id == seq_b.id
      assert s1.pin_id == svv_b.id
      assert s1.pin_type == :sequence_vv

      # position 2 = seq_c (no SVV → unresolvable)
      assert s2.sequence_id == seq_c.id
      assert is_nil(s2.pin_id)

      # position 3 = seq_a (has svv_a)
      assert s3.sequence_id == seq_a.id
      assert s3.pin_id == svv_a.id
      assert s3.pin_type == :sequence_vv
    end
  end
end
