defmodule Storybox.Stories.SegmentThroughlineCastVvResolverTest do
  use Storybox.DataCase

  require Ash.Query

  setup do
    {:ok, user} =
      Storybox.Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "seg_tlcastvv_test@example.com",
        password: "password123!",
        password_confirmation: "password123!"
      })
      |> Ash.create()

    {:ok, story} =
      Storybox.Stories.Story
      |> Ash.Changeset.for_create(:create, %{title: "Test Story", user_id: user.id})
      |> Ash.create()

    {:ok, cast_view} =
      Storybox.Stories.ThroughlineCastView
      |> Ash.ActionInput.for_action(:ensure_for_story, %{story_id: story.id})
      |> Ash.run_action()

    {:ok, cast_vv1} =
      Storybox.Stories.ThroughlineCastViewVersion
      |> Ash.ActionInput.for_action(:cut, %{throughline_cast_view_id: cast_view.id})
      |> Ash.run_action()

    {:ok, top_view} =
      Storybox.Stories.ThroughlineView
      |> Ash.ActionInput.for_action(:ensure_for_story, %{story_id: story.id})
      |> Ash.run_action()

    # A top-level Segment pinning the *first* version of the cast stack.
    {:ok, top_vv} =
      Storybox.Stories.ThroughlineViewVersion
      |> Ash.ActionInput.for_action(:cut, %{
        throughline_view_id: top_view.id,
        segments: [
          %{
            "pin_id" => cast_vv1.id,
            "pin_type" => :throughline_cast_vv,
            "pin_version_at_creation" => cast_vv1.version_number
          }
        ]
      })
      |> Ash.run_action()

    [segment] =
      Storybox.Stories.Segment
      |> Ash.Query.filter(view_version_id == ^top_vv.id)
      |> Ash.read!(authorize?: false)

    %{cast_view: cast_view, cast_vv1: cast_vv1, segment: segment}
  end

  test "resolve_pin/1 resolves a :throughline_cast_vv pin without raising", %{
    segment: segment,
    cast_vv1: cast_vv1
  } do
    assert {:resolved, %Storybox.Stories.ThroughlineCastViewVersion{} = resolved} =
             Storybox.Stories.Segment.resolve_pin(segment)

    assert resolved.id == cast_vv1.id
  end

  test "pin_target_latest_version/1 returns the lineage max after a second cut", %{
    segment: segment,
    cast_view: cast_view
  } do
    assert Storybox.Stories.Segment.pin_target_latest_version(segment) == 1

    {:ok, cast_vv2} =
      Storybox.Stories.ThroughlineCastViewVersion
      |> Ash.ActionInput.for_action(:cut, %{throughline_cast_view_id: cast_view.id})
      |> Ash.run_action()

    assert cast_vv2.version_number == 2
    assert Storybox.Stories.Segment.pin_target_latest_version(segment) == 2
    assert segment.pin_version_at_creation == 1
  end

  test "another story's cast view versions do not affect the lineage max", %{
    segment: segment,
    cast_view: cast_view
  } do
    {:ok, other_story} =
      Storybox.Stories.Story
      |> Ash.Changeset.for_create(:create, %{
        title: "Other Story",
        user_id: Storybox.Stories.Story |> Ash.get!(cast_view.story_id) |> Map.get(:user_id)
      })
      |> Ash.create()

    {:ok, other_cast_view} =
      Storybox.Stories.ThroughlineCastView
      |> Ash.ActionInput.for_action(:ensure_for_story, %{story_id: other_story.id})
      |> Ash.run_action()

    Enum.each(1..3, fn _ ->
      {:ok, _} =
        Storybox.Stories.ThroughlineCastViewVersion
        |> Ash.ActionInput.for_action(:cut, %{throughline_cast_view_id: other_cast_view.id})
        |> Ash.run_action()
    end)

    assert Storybox.Stories.Segment.pin_target_latest_version(segment) == 1
  end
end
