defmodule Storybox.Stories.SequenceViewVersionTest do
  use Storybox.DataCase

  alias Storybox.Stories.{
    Segment,
    ScriptView,
    ScriptViewVersion,
    SequenceView,
    SequenceViewVersion
  }

  require Ash.Query

  setup do
    {:ok, user} =
      Storybox.Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "svv_seq_test@example.com",
        password: "password123!",
        password_confirmation: "password123!"
      })
      |> Ash.create()

    {:ok, story} =
      Storybox.Stories.Story
      |> Ash.Changeset.for_create(:create, %{title: "Test Story", user_id: user.id})
      |> Ash.create()

    sequence =
      Storybox.Stories.Sequence
      |> Ash.Query.filter(story_id == ^story.id)
      |> Ash.read_one!(authorize?: false)

    {:ok, scene} =
      Storybox.Stories.Scene
      |> Ash.Changeset.for_create(:create, %{slug: "opening-scene", story_id: story.id})
      |> Ash.create()

    {:ok, script_view} =
      ScriptView
      |> Ash.ActionInput.for_action(:ensure_for_scene, %{scene_id: scene.id})
      |> Ash.run_action()

    {:ok, piece1} =
      Storybox.Stories.ScriptPiece
      |> Ash.ActionInput.for_action(:create_version, %{
        scene_id: scene.id,
        content: "EXT. PARK - DAY\n\nDraft one."
      })
      |> Ash.run_action()

    {:ok, piece2} =
      Storybox.Stories.ScriptPiece
      |> Ash.ActionInput.for_action(:create_version, %{
        scene_id: scene.id,
        content: "EXT. PARK - DAY\n\nDraft two."
      })
      |> Ash.run_action()

    {:ok, piece3} =
      Storybox.Stories.ScriptPiece
      |> Ash.ActionInput.for_action(:create_version, %{
        scene_id: scene.id,
        content: "EXT. PARK - DAY\n\nDraft three."
      })
      |> Ash.run_action()

    {:ok, svv1} =
      ScriptViewVersion
      |> Ash.ActionInput.for_action(:cut, %{
        script_view_id: script_view.id,
        script_piece_id: piece1.id
      })
      |> Ash.run_action()

    {:ok, svv2} =
      ScriptViewVersion
      |> Ash.ActionInput.for_action(:cut, %{
        script_view_id: script_view.id,
        script_piece_id: piece2.id
      })
      |> Ash.run_action()

    {:ok, svv3} =
      ScriptViewVersion
      |> Ash.ActionInput.for_action(:cut, %{
        script_view_id: script_view.id,
        script_piece_id: piece3.id
      })
      |> Ash.run_action()

    {:ok, sequence_view} =
      SequenceView
      |> Ash.ActionInput.for_action(:ensure_for_sequence, %{
        sequence_id: sequence.id,
        story_id: story.id
      })
      |> Ash.run_action()

    %{
      story: story,
      sequence: sequence,
      scene: scene,
      script_view: script_view,
      svv1: svv1,
      svv2: svv2,
      svv3: svv3,
      sequence_view: sequence_view
    }
  end

  describe "cut" do
    test "creates a SequenceViewVersion with version_number 1 on first call", %{
      sequence_view: sequence_view,
      svv1: svv1,
      svv2: svv2,
      svv3: svv3
    } do
      assert {:ok, vv} =
               SequenceViewVersion
               |> Ash.ActionInput.for_action(:cut, %{
                 sequence_view_id: sequence_view.id,
                 script_view_version_ids: [svv1.id, svv2.id, svv3.id]
               })
               |> Ash.run_action()

      assert vv.version_number == 1
      assert vv.sequence_view_id == sequence_view.id
    end

    test "creates exactly 3 Segments, all with view_version_type :sequence_vv and pin_type :script_vv",
         %{sequence_view: sequence_view, svv1: svv1, svv2: svv2, svv3: svv3} do
      {:ok, vv} =
        SequenceViewVersion
        |> Ash.ActionInput.for_action(:cut, %{
          sequence_view_id: sequence_view.id,
          script_view_version_ids: [svv1.id, svv2.id, svv3.id]
        })
        |> Ash.run_action()

      segments =
        Segment
        |> Ash.Query.filter(view_version_id == ^vv.id)
        |> Ash.read!(authorize?: false)

      assert length(segments) == 3
      assert Enum.all?(segments, &(&1.view_version_type == :sequence_vv))
      assert Enum.all?(segments, &(&1.pin_type == :script_vv))
    end

    test "Segments have positions 1, 2, 3 matching input order", %{
      sequence_view: sequence_view,
      svv1: svv1,
      svv2: svv2,
      svv3: svv3
    } do
      {:ok, vv} =
        SequenceViewVersion
        |> Ash.ActionInput.for_action(:cut, %{
          sequence_view_id: sequence_view.id,
          script_view_version_ids: [svv1.id, svv2.id, svv3.id]
        })
        |> Ash.run_action()

      positions =
        Segment
        |> Ash.Query.filter(view_version_id == ^vv.id)
        |> Ash.Query.sort(:position)
        |> Ash.read!(authorize?: false)
        |> Enum.map(& &1.position)

      assert positions == [1, 2, 3]
    end

    test "each Segment's pin_id and pin_version_at_creation match the corresponding ScriptViewVersion",
         %{sequence_view: sequence_view, svv1: svv1, svv2: svv2, svv3: svv3} do
      {:ok, vv} =
        SequenceViewVersion
        |> Ash.ActionInput.for_action(:cut, %{
          sequence_view_id: sequence_view.id,
          script_view_version_ids: [svv1.id, svv2.id, svv3.id]
        })
        |> Ash.run_action()

      segments =
        Segment
        |> Ash.Query.filter(view_version_id == ^vv.id)
        |> Ash.Query.sort(:position)
        |> Ash.read!(authorize?: false)

      [s1, s2, s3] = segments

      assert s1.pin_id == svv1.id
      assert s1.pin_version_at_creation == svv1.version_number

      assert s2.pin_id == svv2.id
      assert s2.pin_version_at_creation == svv2.version_number

      assert s3.pin_id == svv3.id
      assert s3.pin_version_at_creation == svv3.version_number
    end

    test "second cut produces version_number 2; first VV's Segments are unchanged", %{
      sequence_view: sequence_view,
      svv1: svv1,
      svv2: svv2,
      svv3: svv3
    } do
      {:ok, vv1} =
        SequenceViewVersion
        |> Ash.ActionInput.for_action(:cut, %{
          sequence_view_id: sequence_view.id,
          script_view_version_ids: [svv1.id, svv2.id, svv3.id]
        })
        |> Ash.run_action()

      {:ok, vv2} =
        SequenceViewVersion
        |> Ash.ActionInput.for_action(:cut, %{
          sequence_view_id: sequence_view.id,
          script_view_version_ids: [svv3.id, svv1.id, svv2.id]
        })
        |> Ash.run_action()

      assert vv2.version_number == 2

      v1_pins =
        Segment
        |> Ash.Query.filter(view_version_id == ^vv1.id)
        |> Ash.Query.sort(:position)
        |> Ash.read!(authorize?: false)
        |> Enum.map(& &1.pin_id)

      assert v1_pins == [svv1.id, svv2.id, svv3.id]
    end

    test "Segment.resolve_pin/1 returns {:resolved, %ScriptViewVersion{}} for a :script_vv Segment",
         %{sequence_view: sequence_view, svv1: svv1, svv2: svv2, svv3: svv3} do
      {:ok, vv} =
        SequenceViewVersion
        |> Ash.ActionInput.for_action(:cut, %{
          sequence_view_id: sequence_view.id,
          script_view_version_ids: [svv1.id, svv2.id, svv3.id]
        })
        |> Ash.run_action()

      [first_seg | _] =
        Segment
        |> Ash.Query.filter(view_version_id == ^vv.id)
        |> Ash.Query.sort(:position)
        |> Ash.read!(authorize?: false)

      assert {:resolved, %ScriptViewVersion{id: id}} = Segment.resolve_pin(first_seg)
      assert id == svv1.id
    end
  end
end
