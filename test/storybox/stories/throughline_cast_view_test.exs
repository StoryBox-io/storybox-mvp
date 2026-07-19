defmodule Storybox.Stories.ThroughlineCastViewTest do
  use Storybox.DataCase

  require Ash.Query

  setup do
    {:ok, user} =
      Storybox.Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "tcv_test@example.com",
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
    test "creates the view on first call", %{story: story} do
      assert {:ok, view} =
               Storybox.Stories.ThroughlineCastView
               |> Ash.ActionInput.for_action(:ensure_for_story, %{story_id: story.id})
               |> Ash.run_action()

      assert view.story_id == story.id
    end

    test "is idempotent — a second call returns the same record", %{story: story} do
      {:ok, first} =
        Storybox.Stories.ThroughlineCastView
        |> Ash.ActionInput.for_action(:ensure_for_story, %{story_id: story.id})
        |> Ash.run_action()

      {:ok, second} =
        Storybox.Stories.ThroughlineCastView
        |> Ash.ActionInput.for_action(:ensure_for_story, %{story_id: story.id})
        |> Ash.run_action()

      assert first.id == second.id

      all =
        Storybox.Stories.ThroughlineCastView
        |> Ash.Query.filter(story_id == ^story.id)
        |> Ash.read!(authorize?: false)

      assert length(all) == 1
    end
  end

  describe "create" do
    test "a duplicate story is rejected", %{story: story} do
      {:ok, _view} =
        Storybox.Stories.ThroughlineCastView
        |> Ash.Changeset.for_create(:create, %{story_id: story.id})
        |> Ash.create()

      assert {:error, %Ash.Error.Invalid{}} =
               Storybox.Stories.ThroughlineCastView
               |> Ash.Changeset.for_create(:create, %{story_id: story.id})
               |> Ash.create()
    end
  end
end
