defmodule Storybox.Stories.ScriptViewTest do
  use Storybox.DataCase

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

    {:ok, scene} =
      Storybox.Stories.Scene
      |> Ash.Changeset.for_create(:create, %{slug: "opening-scene", story_id: story.id})
      |> Ash.create()

    %{story: story, scene: scene}
  end

  describe "ensure_for_scene" do
    test "creates a ScriptView when none exists for the scene", %{scene: scene} do
      assert {:ok, view} =
               Storybox.Stories.ScriptView
               |> Ash.ActionInput.for_action(:ensure_for_scene, %{scene_id: scene.id})
               |> Ash.run_action()

      assert view.scene_id == scene.id
    end

    test "returns the existing record on a second call (idempotent)", %{scene: scene} do
      assert {:ok, view1} =
               Storybox.Stories.ScriptView
               |> Ash.ActionInput.for_action(:ensure_for_scene, %{scene_id: scene.id})
               |> Ash.run_action()

      assert {:ok, view2} =
               Storybox.Stories.ScriptView
               |> Ash.ActionInput.for_action(:ensure_for_scene, %{scene_id: scene.id})
               |> Ash.run_action()

      assert view1.id == view2.id
    end

    test "DB unique index rejects a second ScriptView with the same scene_id", %{scene: scene} do
      {:ok, _view} =
        Storybox.Stories.ScriptView
        |> Ash.Changeset.for_create(:create, %{scene_id: scene.id})
        |> Ash.create()

      assert {:error, %Ash.Error.Invalid{}} =
               Storybox.Stories.ScriptView
               |> Ash.Changeset.for_create(:create, %{scene_id: scene.id})
               |> Ash.create()
    end
  end
end
