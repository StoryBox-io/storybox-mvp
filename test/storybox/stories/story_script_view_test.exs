defmodule Storybox.Stories.StoryScriptViewTest do
  use Storybox.DataCase

  require Ash.Query

  setup do
    {:ok, user} =
      Storybox.Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "ssv_test@example.com",
        password: "password123!",
        password_confirmation: "password123!"
      })
      |> Ash.create()

    {:ok, story} =
      Storybox.Stories.Story
      |> Ash.Changeset.for_create(:create, %{title: "Test Story", user_id: user.id})
      |> Ash.create()

    %{story: story}
  end

  describe "ensure_for_story" do
    test "creates a StoryScriptView for the story with correct story_id", %{story: story} do
      assert {:ok, view} =
               Storybox.Stories.StoryScriptView
               |> Ash.ActionInput.for_action(:ensure_for_story, %{story_id: story.id})
               |> Ash.run_action()

      assert view.story_id == story.id
    end

    test "is idempotent — second call returns the same record", %{story: story} do
      assert {:ok, view1} =
               Storybox.Stories.StoryScriptView
               |> Ash.ActionInput.for_action(:ensure_for_story, %{story_id: story.id})
               |> Ash.run_action()

      assert {:ok, view2} =
               Storybox.Stories.StoryScriptView
               |> Ash.ActionInput.for_action(:ensure_for_story, %{story_id: story.id})
               |> Ash.run_action()

      assert view1.id == view2.id

      all =
        Storybox.Stories.StoryScriptView
        |> Ash.Query.filter(story_id == ^story.id)
        |> Ash.read!(authorize?: false)

      assert length(all) == 1
    end

    test "DB unique index rejects a second StoryScriptView for the same story via direct :create",
         %{story: story} do
      {:ok, _view} =
        Storybox.Stories.StoryScriptView
        |> Ash.Changeset.for_create(:create, %{story_id: story.id})
        |> Ash.create()

      assert {:error, %Ash.Error.Invalid{}} =
               Storybox.Stories.StoryScriptView
               |> Ash.Changeset.for_create(:create, %{story_id: story.id})
               |> Ash.create()
    end
  end
end
