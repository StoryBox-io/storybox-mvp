defmodule Storybox.Stories.CharacterThroughlineViewVersionTest do
  use Storybox.DataCase

  require Ash.Query

  setup do
    {:ok, user} =
      Storybox.Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "ctvv_test@example.com",
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

    {:ok, piece} =
      Storybox.Stories.ThroughlinePiece
      |> Ash.ActionInput.for_action(:create_version, %{
        story_id: story.id,
        character_id: character.id,
        content: "Alice learns to trust."
      })
      |> Ash.run_action()

    {:ok, view} =
      Storybox.Stories.CharacterThroughlineView
      |> Ash.ActionInput.for_action(:ensure_for_story_character, %{
        story_id: story.id,
        character_id: character.id
      })
      |> Ash.run_action()

    %{story: story, character: character, piece: piece, view: view}
  end

  defp segments_for(vv) do
    Storybox.Stories.Segment
    |> Ash.Query.filter(view_version_id == ^vv.id)
    |> Ash.Query.sort(position: :asc)
    |> Ash.read!(authorize?: false)
  end

  defp cut(view, args \\ %{}) do
    {:ok, vv} =
      Storybox.Stories.CharacterThroughlineViewVersion
      |> Ash.ActionInput.for_action(
        :cut,
        Map.merge(%{character_throughline_view_id: view.id}, args)
      )
      |> Ash.run_action()

    vv
  end

  describe "cut without explicit segments" do
    test "produces version_number 1 on first call", %{view: view} do
      vv = cut(view)

      assert vv.version_number == 1
      assert vv.character_throughline_view_id == view.id
    end

    test "pins exactly one :throughline_piece at position 1", %{view: view, piece: piece} do
      vv = cut(view)

      assert [seg] = segments_for(vv)
      assert seg.view_version_type == :character_throughline_vv
      assert seg.pin_type == :throughline_piece
      assert seg.pin_id == piece.id
      assert seg.pin_version_at_creation == piece.version_number
      assert seg.position == 1
    end

    test "pins the character's latest ThroughlinePiece", %{
      story: story,
      character: character,
      view: view
    } do
      {:ok, v2} =
        Storybox.Stories.ThroughlinePiece
        |> Ash.ActionInput.for_action(:create_version, %{
          story_id: story.id,
          character_id: character.id,
          content: "Alice learns to trust, reluctantly."
        })
        |> Ash.run_action()

      vv = cut(view)

      assert [seg] = segments_for(vv)
      assert seg.pin_id == v2.id
      assert seg.pin_version_at_creation == 2
    end

    test "produces an empty version when the character has no ThroughlinePiece", %{
      story: story
    } do
      {:ok, bob} =
        Storybox.Stories.Character
        |> Ash.Changeset.for_create(:create, %{name: "Bob", story_id: story.id})
        |> Ash.create()

      {:ok, bob_view} =
        Storybox.Stories.CharacterThroughlineView
        |> Ash.ActionInput.for_action(:ensure_for_story_character, %{
          story_id: story.id,
          character_id: bob.id
        })
        |> Ash.run_action()

      vv = cut(bob_view)

      assert segments_for(vv) == []
    end

    test "second cut increments version_number and leaves the first version untouched", %{
      view: view
    } do
      vv1 = cut(view)
      [seg1] = segments_for(vv1)

      vv2 = cut(view)

      assert vv2.version_number == 2
      assert [reloaded] = segments_for(vv1)
      assert reloaded.id == seg1.id
      assert reloaded.pin_id == seg1.pin_id
      assert reloaded.pin_version_at_creation == seg1.pin_version_at_creation
    end

    test "cutting one character's view produces no segments on another's", %{
      story: story,
      character: character,
      view: view
    } do
      {:ok, bob} =
        Storybox.Stories.Character
        |> Ash.Changeset.for_create(:create, %{name: "Bob", story_id: story.id})
        |> Ash.create()

      {:ok, _bob_piece} =
        Storybox.Stories.ThroughlinePiece
        |> Ash.ActionInput.for_action(:create_version, %{
          story_id: story.id,
          character_id: bob.id,
          content: "Bob stays put."
        })
        |> Ash.run_action()

      {:ok, bob_view} =
        Storybox.Stories.CharacterThroughlineView
        |> Ash.ActionInput.for_action(:ensure_for_story_character, %{
          story_id: story.id,
          character_id: bob.id
        })
        |> Ash.run_action()

      bob_vv = cut(bob_view)
      alice_vv = cut(view)

      [bob_seg] = segments_for(bob_vv)
      [alice_seg] = segments_for(alice_vv)

      {:resolved, bob_piece} = Storybox.Stories.Segment.resolve_pin(bob_seg)
      {:resolved, alice_piece} = Storybox.Stories.Segment.resolve_pin(alice_seg)

      assert bob_piece.character_id == bob.id
      assert alice_piece.character_id == character.id
    end

    test "Segment.resolve_pin/1 returns {:resolved, %ThroughlinePiece{}}", %{
      view: view,
      piece: piece
    } do
      vv = cut(view)
      [seg] = segments_for(vv)

      assert {:resolved, %Storybox.Stories.ThroughlinePiece{} = resolved} =
               Storybox.Stories.Segment.resolve_pin(seg)

      assert resolved.id == piece.id
    end
  end

  describe "cut with explicit segments" do
    test "pins an older ThroughlinePiece version when explicitly supplied", %{
      story: story,
      character: character,
      piece: piece,
      view: view
    } do
      {:ok, _v2} =
        Storybox.Stories.ThroughlinePiece
        |> Ash.ActionInput.for_action(:create_version, %{
          story_id: story.id,
          character_id: character.id,
          content: "Alice learns to trust, reluctantly."
        })
        |> Ash.run_action()

      vv =
        cut(view, %{
          segments: [
            %{
              "pin_id" => piece.id,
              "pin_type" => :throughline_piece,
              "pin_version_at_creation" => piece.version_number
            }
          ]
        })

      assert [seg] = segments_for(vv)
      assert seg.pin_id == piece.id
      assert seg.pin_version_at_creation == 1
      assert seg.position == 1
    end

    test "an empty explicit list produces an empty version even when a piece exists", %{
      view: view
    } do
      vv = cut(view, %{segments: []})

      assert segments_for(vv) == []
    end
  end
end
