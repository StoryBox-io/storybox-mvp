defmodule Storybox.Stories.CharacterViewTest do
  use Storybox.DataCase

  require Ash.Query

  setup do
    {:ok, user} =
      Storybox.Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "cv_test@example.com",
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

    %{character: character}
  end

  describe "ensure_for_character" do
    test "creates a CharacterView on first call", %{character: character} do
      assert {:ok, cv} =
               Storybox.Stories.CharacterView
               |> Ash.ActionInput.for_action(:ensure_for_character, %{
                 character_id: character.id
               })
               |> Ash.run_action()

      assert cv.character_id == character.id
    end

    test "is idempotent — second call returns the same record", %{character: character} do
      {:ok, cv1} =
        Storybox.Stories.CharacterView
        |> Ash.ActionInput.for_action(:ensure_for_character, %{character_id: character.id})
        |> Ash.run_action()

      {:ok, cv2} =
        Storybox.Stories.CharacterView
        |> Ash.ActionInput.for_action(:ensure_for_character, %{character_id: character.id})
        |> Ash.run_action()

      assert cv1.id == cv2.id
    end
  end

  describe "direct create" do
    test "succeeds with a unique character_id", %{character: character} do
      assert {:ok, cv} =
               Storybox.Stories.CharacterView
               |> Ash.Changeset.for_create(:create, %{character_id: character.id})
               |> Ash.create()

      assert cv.character_id == character.id
    end

    test "raises unique-constraint error on duplicate character_id", %{character: character} do
      {:ok, _} =
        Storybox.Stories.CharacterView
        |> Ash.Changeset.for_create(:create, %{character_id: character.id})
        |> Ash.create()

      assert {:error, %Ash.Error.Invalid{}} =
               Storybox.Stories.CharacterView
               |> Ash.Changeset.for_create(:create, %{character_id: character.id})
               |> Ash.create()
    end
  end
end
