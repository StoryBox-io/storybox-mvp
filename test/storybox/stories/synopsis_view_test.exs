defmodule Storybox.Stories.SynopsisViewTest do
  use Storybox.DataCase

  alias Storybox.Stories.SynopsisView

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
      |> Ash.Changeset.for_create(:create, %{title: "Test Story", user_id: user.id})
      |> Ash.create()

    %{story: story}
  end

  describe "create" do
    test "creates a synopsis view for a story", %{story: story} do
      assert {:ok, view} =
               SynopsisView
               |> Ash.Changeset.for_create(:create, %{story_id: story.id})
               |> Ash.create()

      assert view.story_id == story.id
    end

    test "fails without story_id" do
      assert {:error, %Ash.Error.Invalid{}} =
               SynopsisView
               |> Ash.Changeset.for_create(:create, %{})
               |> Ash.create()
    end

    test "enforces unique constraint — second create for same story fails", %{story: story} do
      {:ok, _first} =
        SynopsisView
        |> Ash.Changeset.for_create(:create, %{story_id: story.id})
        |> Ash.create()

      assert {:error, _} =
               SynopsisView
               |> Ash.Changeset.for_create(:create, %{story_id: story.id})
               |> Ash.create()
    end
  end

  describe "ensure_for_story action" do
    test "creates a SynopsisView when none exists for the story", %{story: story} do
      assert {:ok, view} =
               SynopsisView
               |> Ash.ActionInput.for_action(:ensure_for_story, %{story_id: story.id})
               |> Ash.run_action()

      assert view.story_id == story.id
    end

    test "returns the same record on a second call (idempotent)", %{story: story} do
      {:ok, first} =
        SynopsisView
        |> Ash.ActionInput.for_action(:ensure_for_story, %{story_id: story.id})
        |> Ash.run_action()

      {:ok, second} =
        SynopsisView
        |> Ash.ActionInput.for_action(:ensure_for_story, %{story_id: story.id})
        |> Ash.run_action()

      assert first.id == second.id

      count =
        SynopsisView
        |> Ash.Query.filter(story_id == ^story.id)
        |> Ash.read!(authorize?: false)
        |> length()

      assert count == 1
    end
  end

  describe "read" do
    test "returns the synopsis view for a story", %{story: story} do
      {:ok, view} =
        SynopsisView
        |> Ash.Changeset.for_create(:create, %{story_id: story.id})
        |> Ash.create()

      assert {:ok, views} = SynopsisView |> Ash.read()
      assert Enum.any?(views, &(&1.id == view.id))
    end
  end
end
