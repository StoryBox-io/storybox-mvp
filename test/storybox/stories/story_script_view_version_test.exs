defmodule Storybox.Stories.StoryScriptViewVersionTest do
  use Storybox.DataCase

  alias Storybox.Stories.{
    Segment,
    SequenceView,
    SequenceViewVersion,
    StoryScriptView,
    StoryScriptViewVersion
  }

  require Ash.Query

  # Setup creates:
  #   User → Story (bootstrap: Sequence 1, TreatmentView, TVV v1, SynopsisView, SVV v1)
  #   seq_a, seq_b, seq_c (additional sequences)
  #   SequenceViews and SequenceViewVersions for seq_a, seq_b, seq_c
  #   TreatmentViewVersion v2 with order [seq_a, seq_b, seq_c]
  #   TreatmentViewVersion v3 with order [seq_c, seq_a, seq_b]
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

    {:ok, sv_c} =
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
        script_view_version_ids: []
      })
      |> Ash.run_action()

    # seq_b has a SequenceViewVersion (resolvable)
    {:ok, svv_b} =
      SequenceViewVersion
      |> Ash.ActionInput.for_action(:cut, %{
        sequence_view_id: sv_b.id,
        script_view_version_ids: []
      })
      |> Ash.run_action()

    # seq_c has NO SequenceViewVersion (unresolvable)
    _sv_c = sv_c

    treatment_view =
      Storybox.Stories.TreatmentView
      |> Ash.Query.filter(story_id == ^story.id)
      |> Ash.read_one!(authorize?: false)

    # Destroy bootstrap TVV to control exact ordering
    Storybox.Stories.TreatmentViewVersion
    |> Ash.Query.filter(treatment_view_id == ^treatment_view.id)
    |> Ash.read!(authorize?: false)
    |> Enum.each(&Ash.destroy!(&1, authorize?: false))

    # TVV v1 with order [seq_a, seq_b, seq_c]
    Storybox.Stories.TreatmentViewVersion
    |> Ash.Changeset.for_create(:create, %{
      treatment_view_id: treatment_view.id,
      version_number: 1
    })
    |> Ash.create!(authorize?: false)
    |> tap(fn tvv ->
      [{seq_a.id, 1}, {seq_b.id, 2}, {seq_c.id, 3}]
      |> Enum.each(fn {seq_id, pos} ->
        Storybox.Stories.Segment
        |> Ash.Changeset.for_create(:create, %{
          view_version_id: tvv.id,
          view_version_type: :treatment_vv,
          position: pos,
          sequence_id: seq_id
        })
        |> Ash.create!(authorize?: false)
      end)
    end)

    # TVV v2 with order [seq_c, seq_a, seq_b]
    tvv2 =
      Storybox.Stories.TreatmentViewVersion
      |> Ash.Changeset.for_create(:create, %{
        treatment_view_id: treatment_view.id,
        version_number: 2
      })
      |> Ash.create!(authorize?: false)

    [{seq_c.id, 1}, {seq_a.id, 2}, {seq_b.id, 3}]
    |> Enum.each(fn {seq_id, pos} ->
      Storybox.Stories.Segment
      |> Ash.Changeset.for_create(:create, %{
        view_version_id: tvv2.id,
        view_version_type: :treatment_vv,
        position: pos,
        sequence_id: seq_id
      })
      |> Ash.create!(authorize?: false)
    end)

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
      tvv2: tvv2,
      story_script_view: story_script_view,
      treatment_view: treatment_view
    }
  end

  describe "cut" do
    test "returns error when no TreatmentViewVersion exists for story" do
      {:ok, user2} =
        Storybox.Accounts.User
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: "no_tvv@example.com",
          password: "password123!",
          password_confirmation: "password123!"
        })
        |> Ash.create()

      {:ok, story2} =
        Storybox.Stories.Story
        |> Ash.Changeset.for_create(:create, %{title: "No TVV Story", user_id: user2.id})
        |> Ash.create()

      tv2 =
        Storybox.Stories.TreatmentView
        |> Ash.Query.filter(story_id == ^story2.id)
        |> Ash.read_one!(authorize?: false)

      Storybox.Stories.TreatmentViewVersion
      |> Ash.Query.filter(treatment_view_id == ^tv2.id)
      |> Ash.read!(authorize?: false)
      |> Enum.each(&Ash.destroy!(&1, authorize?: false))

      {:ok, ssv2} =
        StoryScriptView
        |> Ash.ActionInput.for_action(:ensure_for_story, %{story_id: story2.id})
        |> Ash.run_action()

      error =
        assert_raise Ash.Error.Unknown, fn ->
          StoryScriptViewVersion
          |> Ash.ActionInput.for_action(:cut, %{story_script_view_id: ssv2.id})
          |> Ash.run_action()
        end

      assert Exception.message(error) =~ "no TreatmentViewVersion"
    end

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

    test "source_treatment_view_version_id equals the latest TVV's id", %{
      story_script_view: ssv,
      tvv2: tvv2
    } do
      {:ok, vv} =
        StoryScriptViewVersion
        |> Ash.ActionInput.for_action(:cut, %{story_script_view_id: ssv.id})
        |> Ash.run_action()

      assert vv.source_treatment_view_version_id == tvv2.id
    end

    test "Segments have view_version_type :story_script_vv", %{story_script_view: ssv} do
      {:ok, vv} =
        StoryScriptViewVersion
        |> Ash.ActionInput.for_action(:cut, %{story_script_view_id: ssv.id})
        |> Ash.run_action()

      segments =
        Segment
        |> Ash.Query.filter(view_version_id == ^vv.id)
        |> Ash.read!(authorize?: false)

      assert length(segments) == 3
      assert Enum.all?(segments, &(&1.view_version_type == :story_script_vv))
    end

    test "Segments pin SequenceViewVersions in the order from the source TVV", %{
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

      # TVV v2 order: [seq_c, seq_a, seq_b] — positions 1, 2, 3
      segments =
        Segment
        |> Ash.Query.filter(view_version_id == ^vv.id)
        |> Ash.Query.sort(:position)
        |> Ash.read!(authorize?: false)

      [s1, s2, s3] = segments

      # position 1 = seq_c (no SVV → unresolvable)
      assert is_nil(s1.pin_id)
      assert is_nil(s1.pin_type)
      # sequence_id nil per orchestrator Q1
      assert is_nil(s1.sequence_id)

      # position 2 = seq_a (has svv_a)
      assert s2.pin_id == svv_a.id
      assert s2.pin_type == :sequence_vv
      assert s2.pin_version_at_creation == svv_a.version_number
      assert is_nil(s2.sequence_id)

      # position 3 = seq_b (has svv_b)
      assert s3.pin_id == svv_b.id
      assert s3.pin_type == :sequence_vv
      assert s3.pin_version_at_creation == svv_b.version_number
      assert is_nil(s3.sequence_id)

      # suppress unused variable warnings
      _ = seq_a
      _ = seq_b
      _ = seq_c
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

      # position 1 = seq_c (unresolvable = nil), position 2 = seq_a, position 3 = seq_b
      assert v1_pin_ids == [nil, svv_a.id, svv_b.id]
    end

    test "Segment.resolve_pin/1 returns {:resolved, %SequenceViewVersion{}} for a :sequence_vv Segment",
         %{story_script_view: ssv, svv_a: svv_a} do
      {:ok, vv} =
        StoryScriptViewVersion
        |> Ash.ActionInput.for_action(:cut, %{story_script_view_id: ssv.id})
        |> Ash.run_action()

      # position 2 = seq_a = svv_a (resolvable)
      pinned_seg =
        Segment
        |> Ash.Query.filter(view_version_id == ^vv.id and not is_nil(pin_id))
        |> Ash.Query.sort(:position)
        |> Ash.read!(authorize?: false)
        |> List.first()

      assert {:resolved, %SequenceViewVersion{id: id}} = Segment.resolve_pin(pinned_seg)
      assert id == svv_a.id
    end

    test "DataCase: TVV order change is reflected in a new StoryScriptVV cut", %{
      story: story,
      story_script_view: ssv,
      seq_a: seq_a,
      seq_b: seq_b,
      seq_c: seq_c,
      svv_a: svv_a,
      svv_b: svv_b,
      treatment_view: treatment_view
    } do
      # TVV v3 with order [seq_c, seq_a, seq_b] already set as latest from setup (tvv2)
      # Now create TVV v3 with a different order [seq_b, seq_c, seq_a]
      tvv3 =
        Storybox.Stories.TreatmentViewVersion
        |> Ash.Changeset.for_create(:create, %{
          treatment_view_id: treatment_view.id,
          version_number: 3
        })
        |> Ash.create!(authorize?: false)

      [{seq_b.id, 1}, {seq_c.id, 2}, {seq_a.id, 3}]
      |> Enum.each(fn {seq_id, pos} ->
        Storybox.Stories.Segment
        |> Ash.Changeset.for_create(:create, %{
          view_version_id: tvv3.id,
          view_version_type: :treatment_vv,
          position: pos,
          sequence_id: seq_id
        })
        |> Ash.create!(authorize?: false)
      end)

      {:ok, vv} =
        StoryScriptViewVersion
        |> Ash.ActionInput.for_action(:cut, %{story_script_view_id: ssv.id})
        |> Ash.run_action()

      assert vv.source_treatment_view_version_id == tvv3.id

      segments =
        Segment
        |> Ash.Query.filter(view_version_id == ^vv.id)
        |> Ash.Query.sort(:position)
        |> Ash.read!(authorize?: false)

      [s1, s2, s3] = segments

      # position 1 = seq_b (has svv_b)
      assert s1.pin_id == svv_b.id
      assert s1.pin_type == :sequence_vv

      # position 2 = seq_c (no SVV → unresolvable)
      assert is_nil(s2.pin_id)

      # position 3 = seq_a (has svv_a)
      assert s3.pin_id == svv_a.id
      assert s3.pin_type == :sequence_vv

      _ = story
    end
  end
end
