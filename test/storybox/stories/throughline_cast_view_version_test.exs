defmodule Storybox.Stories.ThroughlineCastViewVersionTest do
  use Storybox.DataCase

  require Ash.Query

  setup do
    {:ok, user} =
      Storybox.Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "tcvv_test@example.com",
        password: "password123!",
        password_confirmation: "password123!"
      })
      |> Ash.create()

    {:ok, story} =
      Storybox.Stories.Story
      |> Ash.Changeset.for_create(:create, %{title: "Test Story", user_id: user.id})
      |> Ash.create()

    [alice_vv, bob_vv] =
      Enum.map(["Alice", "Bob"], fn name ->
        {:ok, character} =
          Storybox.Stories.Character
          |> Ash.Changeset.for_create(:create, %{name: name, story_id: story.id})
          |> Ash.create()

        {:ok, _piece} =
          Storybox.Stories.ThroughlinePiece
          |> Ash.ActionInput.for_action(:create_version, %{
            story_id: story.id,
            character_id: character.id,
            content: "#{name}'s arc."
          })
          |> Ash.run_action()

        {:ok, view} =
          Storybox.Stories.CharacterThroughlineView
          |> Ash.ActionInput.for_action(:ensure_for_story_character, %{
            story_id: story.id,
            character_id: character.id
          })
          |> Ash.run_action()

        {:ok, vv} =
          Storybox.Stories.CharacterThroughlineViewVersion
          |> Ash.ActionInput.for_action(:cut, %{character_throughline_view_id: view.id})
          |> Ash.run_action()

        vv
      end)

    {:ok, cast_view} =
      Storybox.Stories.ThroughlineCastView
      |> Ash.ActionInput.for_action(:ensure_for_story, %{story_id: story.id})
      |> Ash.run_action()

    %{cast_view: cast_view, alice_vv: alice_vv, bob_vv: bob_vv}
  end

  defp segments_for(vv) do
    Storybox.Stories.Segment
    |> Ash.Query.filter(view_version_id == ^vv.id)
    |> Ash.Query.sort(position: :asc)
    |> Ash.read!(authorize?: false)
  end

  defp segment_map(vv) do
    %{
      "pin_id" => vv.id,
      "pin_type" => :throughline_vv,
      "pin_version_at_creation" => vv.version_number
    }
  end

  defp cut(cast_view, args \\ %{}) do
    {:ok, vv} =
      Storybox.Stories.ThroughlineCastViewVersion
      |> Ash.ActionInput.for_action(
        :cut,
        Map.merge(%{throughline_cast_view_id: cast_view.id}, args)
      )
      |> Ash.run_action()

    vv
  end

  describe "cut" do
    test "with an explicit segments list writes Segments at position 1..N in order", %{
      cast_view: cast_view,
      alice_vv: alice_vv,
      bob_vv: bob_vv
    } do
      vv = cut(cast_view, %{segments: [segment_map(bob_vv), segment_map(alice_vv)]})

      assert vv.version_number == 1

      assert [first, second] = segments_for(vv)

      assert first.position == 1
      assert first.view_version_type == :throughline_cast_vv
      assert first.pin_type == :throughline_vv
      assert first.pin_id == bob_vv.id
      assert first.pin_version_at_creation == bob_vv.version_number

      assert second.position == 2
      assert second.pin_id == alice_vv.id
    end

    test "with no segments argument produces an empty version", %{cast_view: cast_view} do
      vv = cut(cast_view)

      assert vv.version_number == 1
      assert segments_for(vv) == []
    end

    test "second cut increments version_number and leaves prior Segments untouched", %{
      cast_view: cast_view,
      alice_vv: alice_vv,
      bob_vv: bob_vv
    } do
      vv1 = cut(cast_view, %{segments: [segment_map(alice_vv)]})
      [seg1] = segments_for(vv1)

      vv2 = cut(cast_view, %{segments: [segment_map(bob_vv)]})

      assert vv2.version_number == 2

      assert [reloaded] = segments_for(vv1)
      assert reloaded.id == seg1.id
      assert reloaded.pin_id == alice_vv.id

      assert [seg2] = segments_for(vv2)
      assert seg2.pin_id == bob_vv.id
    end

    test "Segment.resolve_pin/1 resolves a :throughline_vv pin to a CharacterThroughlineViewVersion",
         %{cast_view: cast_view, alice_vv: alice_vv} do
      vv = cut(cast_view, %{segments: [segment_map(alice_vv)]})
      [seg] = segments_for(vv)

      assert {:resolved, %Storybox.Stories.CharacterThroughlineViewVersion{} = resolved} =
               Storybox.Stories.Segment.resolve_pin(seg)

      assert resolved.id == alice_vv.id
    end
  end
end
