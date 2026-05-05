defmodule Storybox.Stories.CharacterViewVersionTest do
  use Storybox.DataCase

  require Ash.Query

  setup do
    {:ok, user} =
      Storybox.Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "cvv_test@example.com",
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
      Storybox.Stories.CharacterPiece
      |> Ash.ActionInput.for_action(:create_version, %{
        character_id: character.id,
        content: "Essence: The hero.\n\nVoice: Bold."
      })
      |> Ash.run_action()

    {:ok, character_view} =
      Storybox.Stories.CharacterView
      |> Ash.ActionInput.for_action(:ensure_for_character, %{character_id: character.id})
      |> Ash.run_action()

    %{character_view: character_view, piece: piece}
  end

  describe "cut" do
    test "creates a CharacterViewVersion with version_number 1 on first call", %{
      character_view: cv
    } do
      assert {:ok, vv} =
               Storybox.Stories.CharacterViewVersion
               |> Ash.ActionInput.for_action(:cut, %{character_view_id: cv.id})
               |> Ash.run_action()

      assert vv.version_number == 1
      assert vv.character_view_id == cv.id
    end

    test "creates exactly one Segment with view_version_type :character_vv", %{
      character_view: cv
    } do
      {:ok, vv} =
        Storybox.Stories.CharacterViewVersion
        |> Ash.ActionInput.for_action(:cut, %{character_view_id: cv.id})
        |> Ash.run_action()

      segments =
        Storybox.Stories.Segment
        |> Ash.Query.filter(view_version_id == ^vv.id)
        |> Ash.read!(authorize?: false)

      assert length(segments) == 1
      [seg] = segments
      assert seg.view_version_type == :character_vv
    end

    test "Segment carries correct pin_id, pin_type, pin_version_at_creation, and position", %{
      character_view: cv,
      piece: piece
    } do
      {:ok, vv} =
        Storybox.Stories.CharacterViewVersion
        |> Ash.ActionInput.for_action(:cut, %{character_view_id: cv.id})
        |> Ash.run_action()

      [seg] =
        Storybox.Stories.Segment
        |> Ash.Query.filter(view_version_id == ^vv.id)
        |> Ash.read!(authorize?: false)

      assert seg.pin_id == piece.id
      assert seg.pin_type == :character_piece
      assert seg.pin_version_at_creation == piece.version_number
      assert seg.position == 1
    end

    test "second cut produces version_number 2", %{character_view: cv} do
      {:ok, _vv1} =
        Storybox.Stories.CharacterViewVersion
        |> Ash.ActionInput.for_action(:cut, %{character_view_id: cv.id})
        |> Ash.run_action()

      {:ok, vv2} =
        Storybox.Stories.CharacterViewVersion
        |> Ash.ActionInput.for_action(:cut, %{character_view_id: cv.id})
        |> Ash.run_action()

      assert vv2.version_number == 2
    end

    test "Segment.resolve_pin/1 returns {:resolved, %CharacterPiece{}}", %{
      character_view: cv,
      piece: piece
    } do
      {:ok, vv} =
        Storybox.Stories.CharacterViewVersion
        |> Ash.ActionInput.for_action(:cut, %{character_view_id: cv.id})
        |> Ash.run_action()

      [seg] =
        Storybox.Stories.Segment
        |> Ash.Query.filter(view_version_id == ^vv.id)
        |> Ash.read!(authorize?: false)

      assert {:resolved, resolved_piece} = Storybox.Stories.Segment.resolve_pin(seg)
      assert resolved_piece.id == piece.id
      assert resolved_piece.content_uri == piece.content_uri
    end
  end
end
