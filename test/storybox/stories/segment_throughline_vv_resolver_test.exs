defmodule Storybox.Stories.SegmentThroughlineVvResolverTest do
  use Storybox.DataCase

  require Ash.Query

  setup do
    {:ok, user} =
      Storybox.Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "seg_tlvv_test@example.com",
        password: "password123!",
        password_confirmation: "password123!"
      })
      |> Ash.create()

    {:ok, story} =
      Storybox.Stories.Story
      |> Ash.Changeset.for_create(:create, %{title: "Test Story", user_id: user.id})
      |> Ash.create()

    {:ok, character} =
      Storybox.Stories.Character
      |> Ash.Changeset.for_create(:create, %{name: "Alice", story_id: story.id})
      |> Ash.create()

    {:ok, _piece} =
      Storybox.Stories.ThroughlinePiece
      |> Ash.ActionInput.for_action(:create_version, %{
        story_id: story.id,
        character_id: character.id,
        content: "Alice's arc."
      })
      |> Ash.run_action()

    {:ok, view} =
      Storybox.Stories.CharacterThroughlineView
      |> Ash.ActionInput.for_action(:ensure_for_story_character, %{
        story_id: story.id,
        character_id: character.id
      })
      |> Ash.run_action()

    {:ok, vv1} =
      Storybox.Stories.CharacterThroughlineViewVersion
      |> Ash.ActionInput.for_action(:cut, %{character_throughline_view_id: view.id})
      |> Ash.run_action()

    {:ok, cast_view} =
      Storybox.Stories.ThroughlineCastView
      |> Ash.ActionInput.for_action(:ensure_for_story, %{story_id: story.id})
      |> Ash.run_action()

    # A cast Segment pinning the *first* version of Alice's through-line view.
    cast_vv =
      Storybox.Stories.ThroughlineCastViewVersion
      |> Ash.ActionInput.for_action(:cut, %{
        throughline_cast_view_id: cast_view.id,
        segments: [
          %{
            "pin_id" => vv1.id,
            "pin_type" => :throughline_vv,
            "pin_version_at_creation" => vv1.version_number
          }
        ]
      })
      |> Ash.run_action()
      |> then(fn {:ok, vv} -> vv end)

    [segment] =
      Storybox.Stories.Segment
      |> Ash.Query.filter(view_version_id == ^cast_vv.id)
      |> Ash.read!(authorize?: false)

    %{view: view, vv1: vv1, segment: segment}
  end

  test "resolve_pin/1 resolves a :throughline_vv pin without raising", %{
    segment: segment,
    vv1: vv1
  } do
    assert {:resolved, %Storybox.Stories.CharacterThroughlineViewVersion{} = resolved} =
             Storybox.Stories.Segment.resolve_pin(segment)

    assert resolved.id == vv1.id
  end

  test "pin_target_latest_version/1 returns the pinned version when it is the only one", %{
    segment: segment
  } do
    assert Storybox.Stories.Segment.pin_target_latest_version(segment) == 1
  end

  test "pin_target_latest_version/1 returns the lineage max after a second cut", %{
    segment: segment,
    view: view
  } do
    {:ok, vv2} =
      Storybox.Stories.CharacterThroughlineViewVersion
      |> Ash.ActionInput.for_action(:cut, %{character_throughline_view_id: view.id})
      |> Ash.run_action()

    assert vv2.version_number == 2
    assert Storybox.Stories.Segment.pin_target_latest_version(segment) == 2
    assert segment.pin_version_at_creation == 1
  end

  test "another character's view versions do not affect the lineage max", %{
    segment: segment,
    view: view
  } do
    story_id = view.story_id

    {:ok, bob} =
      Storybox.Stories.Character
      |> Ash.Changeset.for_create(:create, %{name: "Bob", story_id: story_id})
      |> Ash.create()

    {:ok, bob_view} =
      Storybox.Stories.CharacterThroughlineView
      |> Ash.ActionInput.for_action(:ensure_for_story_character, %{
        story_id: story_id,
        character_id: bob.id
      })
      |> Ash.run_action()

    Enum.each(1..3, fn _ ->
      {:ok, _} =
        Storybox.Stories.CharacterThroughlineViewVersion
        |> Ash.ActionInput.for_action(:cut, %{character_throughline_view_id: bob_view.id})
        |> Ash.run_action()
    end)

    assert Storybox.Stories.Segment.pin_target_latest_version(segment) == 1
  end
end
