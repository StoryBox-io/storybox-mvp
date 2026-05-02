defmodule Storybox.Stories.SynopsisViewVersionTest do
  use Storybox.DataCase

  alias Storybox.Stories.{
    SynopsisView,
    SynopsisViewVersion,
    Segment,
    SynopsisPiece
  }

  require Ash.Query

  setup do
    {:ok, user} =
      Storybox.Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "test@example.com",
        password: "password123!",
        password_confirmation: "password123!"
      })
      |> Ash.create()

    {:ok, story} =
      Storybox.Stories.Story
      |> Ash.Changeset.for_create(:create, %{title: "Little Witch", user_id: user.id})
      |> Ash.create()

    {:ok, seq1} =
      Storybox.Stories.Sequence
      |> Ash.Changeset.for_create(:create, %{
        name: "Prologue",
        slug: "prologue",
        story_id: story.id
      })
      |> Ash.create()

    {:ok, seq2} =
      Storybox.Stories.Sequence
      |> Ash.Changeset.for_create(:create, %{
        name: "Forest",
        slug: "forest",
        story_id: story.id
      })
      |> Ash.create()

    {:ok, seq3} =
      Storybox.Stories.Sequence
      |> Ash.Changeset.for_create(:create, %{
        name: "Capital",
        slug: "capital",
        story_id: story.id
      })
      |> Ash.create()

    # seq1 (prologue) has two pieces; seq2 (forest) has one; seq3 (capital) has none
    {:ok, p1a} =
      SynopsisPiece
      |> Ash.Changeset.for_create(:create, %{
        story_id: story.id,
        sequence_id: seq1.id,
        content_uri: "storybox://s/prologue/v1.fountain",
        version_number: 1
      })
      |> Ash.create()

    {:ok, p1b} =
      SynopsisPiece
      |> Ash.Changeset.for_create(:create, %{
        story_id: story.id,
        sequence_id: seq1.id,
        content_uri: "storybox://s/prologue/v2.fountain",
        version_number: 2
      })
      |> Ash.create()

    {:ok, p2} =
      SynopsisPiece
      |> Ash.Changeset.for_create(:create, %{
        story_id: story.id,
        sequence_id: seq2.id,
        content_uri: "storybox://s/forest/v1.fountain",
        version_number: 1
      })
      |> Ash.create()

    {:ok, synopsis_view} =
      SynopsisView
      |> Ash.ActionInput.for_action(:ensure_for_story, %{story_id: story.id})
      |> Ash.run_action()

    %{
      story: story,
      seq1: seq1,
      seq2: seq2,
      seq3: seq3,
      p1a: p1a,
      p1b: p1b,
      p2: p2,
      synopsis_view: synopsis_view
    }
  end

  describe "cut action" do
    test "creates a SynopsisViewVersion with version_number 1 on first cut", %{
      synopsis_view: synopsis_view
    } do
      assert {:ok, vv} =
               SynopsisViewVersion
               |> Ash.ActionInput.for_action(:cut, %{synopsis_view_id: synopsis_view.id})
               |> Ash.run_action()

      assert vv.synopsis_view_id == synopsis_view.id
      assert vv.version_number == 1
    end

    test "creates exactly 3 Segments — one per Sequence", %{synopsis_view: synopsis_view} do
      {:ok, vv} =
        SynopsisViewVersion
        |> Ash.ActionInput.for_action(:cut, %{synopsis_view_id: synopsis_view.id})
        |> Ash.run_action()

      segments =
        Segment
        |> Ash.Query.filter(view_version_id == ^vv.id and view_version_type == :synopsis_vv)
        |> Ash.read!(authorize?: false)

      assert length(segments) == 3
    end

    test "prologue Segment pins prologue-v2 (latest piece)", %{
      synopsis_view: synopsis_view,
      seq1: seq1,
      p1b: p1b
    } do
      {:ok, vv} =
        SynopsisViewVersion
        |> Ash.ActionInput.for_action(:cut, %{synopsis_view_id: synopsis_view.id})
        |> Ash.run_action()

      [prologue_seg] =
        Segment
        |> Ash.Query.filter(
          view_version_id == ^vv.id and
            view_version_type == :synopsis_vv and
            sequence_id == ^seq1.id
        )
        |> Ash.read!(authorize?: false)

      assert prologue_seg.pin_id == p1b.id
      assert prologue_seg.pin_type == :synopsis_piece
      assert prologue_seg.pin_version_at_creation == 2
    end

    test "forest Segment pins forest-v1", %{
      synopsis_view: synopsis_view,
      seq2: seq2,
      p2: p2
    } do
      {:ok, vv} =
        SynopsisViewVersion
        |> Ash.ActionInput.for_action(:cut, %{synopsis_view_id: synopsis_view.id})
        |> Ash.run_action()

      [forest_seg] =
        Segment
        |> Ash.Query.filter(
          view_version_id == ^vv.id and
            view_version_type == :synopsis_vv and
            sequence_id == ^seq2.id
        )
        |> Ash.read!(authorize?: false)

      assert forest_seg.pin_id == p2.id
      assert forest_seg.pin_type == :synopsis_piece
      assert forest_seg.pin_version_at_creation == 1
    end

    test "capital Segment is unresolvable and does not raise", %{
      synopsis_view: synopsis_view,
      seq3: seq3
    } do
      {:ok, vv} =
        SynopsisViewVersion
        |> Ash.ActionInput.for_action(:cut, %{synopsis_view_id: synopsis_view.id})
        |> Ash.run_action()

      [capital_seg] =
        Segment
        |> Ash.Query.filter(
          view_version_id == ^vv.id and
            view_version_type == :synopsis_vv and
            sequence_id == ^seq3.id
        )
        |> Ash.read!(authorize?: false)

      assert capital_seg.pin_id == nil
      assert capital_seg.pin_type == nil
      assert capital_seg.pin_version_at_creation == nil
      assert capital_seg.sequence_id == seq3.id
    end

    test "second cut increments version_number to 2", %{synopsis_view: synopsis_view} do
      {:ok, _vv1} =
        SynopsisViewVersion
        |> Ash.ActionInput.for_action(:cut, %{synopsis_view_id: synopsis_view.id})
        |> Ash.run_action()

      {:ok, vv2} =
        SynopsisViewVersion
        |> Ash.ActionInput.for_action(:cut, %{synopsis_view_id: synopsis_view.id})
        |> Ash.run_action()

      assert vv2.version_number == 2
    end

    test "v2 pins the new piece version while v1's pin remains unchanged", %{
      synopsis_view: synopsis_view,
      seq1: seq1,
      story: story,
      p1b: p1b
    } do
      {:ok, vv1} =
        SynopsisViewVersion
        |> Ash.ActionInput.for_action(:cut, %{synopsis_view_id: synopsis_view.id})
        |> Ash.run_action()

      # Advance prologue to v3
      {:ok, p1c} =
        SynopsisPiece
        |> Ash.Changeset.for_create(:create, %{
          story_id: story.id,
          sequence_id: seq1.id,
          content_uri: "storybox://s/prologue/v3.fountain",
          version_number: 3
        })
        |> Ash.create()

      {:ok, vv2} =
        SynopsisViewVersion
        |> Ash.ActionInput.for_action(:cut, %{synopsis_view_id: synopsis_view.id})
        |> Ash.run_action()

      [seg_v1] =
        Segment
        |> Ash.Query.filter(
          view_version_id == ^vv1.id and
            view_version_type == :synopsis_vv and
            sequence_id == ^seq1.id
        )
        |> Ash.read!(authorize?: false)

      [seg_v2] =
        Segment
        |> Ash.Query.filter(
          view_version_id == ^vv2.id and
            view_version_type == :synopsis_vv and
            sequence_id == ^seq1.id
        )
        |> Ash.read!(authorize?: false)

      # v1's pin is unchanged (still prologue-v2)
      assert seg_v1.pin_id == p1b.id
      assert seg_v1.pin_version_at_creation == 2

      # v2 pins prologue-v3
      assert seg_v2.pin_id == p1c.id
      assert seg_v2.pin_version_at_creation == 3
    end
  end

  describe "Segment.resolve_pin/1 for synopsis_piece" do
    test "resolves a pinned synopsis Segment to the SynopsisPiece struct", %{
      synopsis_view: synopsis_view,
      seq1: seq1,
      p1b: p1b
    } do
      {:ok, vv} =
        SynopsisViewVersion
        |> Ash.ActionInput.for_action(:cut, %{synopsis_view_id: synopsis_view.id})
        |> Ash.run_action()

      [prologue_seg] =
        Segment
        |> Ash.Query.filter(
          view_version_id == ^vv.id and
            view_version_type == :synopsis_vv and
            sequence_id == ^seq1.id
        )
        |> Ash.read!(authorize?: false)

      assert {:resolved, %SynopsisPiece{id: id}} = Segment.resolve_pin(prologue_seg)
      assert id == p1b.id
    end
  end

  describe "Segment.pin_target_latest_version/1 for synopsis_piece" do
    test "returns 3 after prologue-v3 is added", %{
      synopsis_view: synopsis_view,
      seq1: seq1,
      story: story
    } do
      {:ok, vv} =
        SynopsisViewVersion
        |> Ash.ActionInput.for_action(:cut, %{synopsis_view_id: synopsis_view.id})
        |> Ash.run_action()

      {:ok, _p1c} =
        SynopsisPiece
        |> Ash.Changeset.for_create(:create, %{
          story_id: story.id,
          sequence_id: seq1.id,
          content_uri: "storybox://s/prologue/v3.fountain",
          version_number: 3
        })
        |> Ash.create()

      [prologue_seg] =
        Segment
        |> Ash.Query.filter(
          view_version_id == ^vv.id and
            view_version_type == :synopsis_vv and
            sequence_id == ^seq1.id
        )
        |> Ash.read!(authorize?: false)

      assert Segment.pin_target_latest_version(prologue_seg) == 3
    end
  end
end
