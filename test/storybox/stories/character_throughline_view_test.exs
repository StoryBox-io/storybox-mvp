defmodule Storybox.Stories.CharacterThroughlineViewTest do
  use Storybox.DataCase

  require Ash.Query

  setup do
    {:ok, user} =
      Storybox.Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "ctv_test@example.com",
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

    %{story: story, character: character}
  end

  describe "ensure_for_story_character" do
    test "creates the view on first call", %{story: story, character: character} do
      assert {:ok, view} =
               Storybox.Stories.CharacterThroughlineView
               |> Ash.ActionInput.for_action(:ensure_for_story_character, %{
                 story_id: story.id,
                 character_id: character.id
               })
               |> Ash.run_action()

      assert view.story_id == story.id
      assert view.character_id == character.id
    end

    test "is idempotent — a second call returns the same record", %{
      story: story,
      character: character
    } do
      {:ok, first} =
        Storybox.Stories.CharacterThroughlineView
        |> Ash.ActionInput.for_action(:ensure_for_story_character, %{
          story_id: story.id,
          character_id: character.id
        })
        |> Ash.run_action()

      {:ok, second} =
        Storybox.Stories.CharacterThroughlineView
        |> Ash.ActionInput.for_action(:ensure_for_story_character, %{
          story_id: story.id,
          character_id: character.id
        })
        |> Ash.run_action()

      assert first.id == second.id

      all =
        Storybox.Stories.CharacterThroughlineView
        |> Ash.Query.filter(story_id == ^story.id)
        |> Ash.read!(authorize?: false)

      assert length(all) == 1
    end

    test "a second character in the same story gets its own view", %{
      story: story,
      character: character
    } do
      {:ok, other} =
        Storybox.Stories.Character
        |> Ash.Changeset.for_create(:create, %{name: "Bob", story_id: story.id})
        |> Ash.create()

      {:ok, alice_view} =
        Storybox.Stories.CharacterThroughlineView
        |> Ash.ActionInput.for_action(:ensure_for_story_character, %{
          story_id: story.id,
          character_id: character.id
        })
        |> Ash.run_action()

      {:ok, bob_view} =
        Storybox.Stories.CharacterThroughlineView
        |> Ash.ActionInput.for_action(:ensure_for_story_character, %{
          story_id: story.id,
          character_id: other.id
        })
        |> Ash.run_action()

      refute alice_view.id == bob_view.id
    end
  end

  describe "create" do
    test "succeeds for a fresh (story, character) pair", %{story: story, character: character} do
      assert {:ok, _view} =
               Storybox.Stories.CharacterThroughlineView
               |> Ash.Changeset.for_create(:create, %{
                 story_id: story.id,
                 character_id: character.id
               })
               |> Ash.create()
    end

    test "a duplicate (story, character) pair is rejected", %{
      story: story,
      character: character
    } do
      {:ok, _view} =
        Storybox.Stories.CharacterThroughlineView
        |> Ash.Changeset.for_create(:create, %{
          story_id: story.id,
          character_id: character.id
        })
        |> Ash.create()

      assert {:error, %Ash.Error.Invalid{}} =
               Storybox.Stories.CharacterThroughlineView
               |> Ash.Changeset.for_create(:create, %{
                 story_id: story.id,
                 character_id: character.id
               })
               |> Ash.create()
    end
  end
end
