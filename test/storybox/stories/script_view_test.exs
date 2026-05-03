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
      |> Ash.Changeset.for_create(:create, %{title: "Opening Scene", story_id: story.id})
      |> Ash.create()

    %{story: story, scene: scene}
  end

  describe "create script_view" do
    test "creates a script_view with required fields", %{scene: scene} do
      assert {:ok, view} =
               Storybox.Stories.ScriptView
               |> Ash.Changeset.for_create(:create, %{
                 title: "Opening Scene",
                 scene_id: scene.id
               })
               |> Ash.create()

      assert view.title == "Opening Scene"
      assert view.scene_id == scene.id
      assert is_nil(view.approved_version_id)
    end

    test "fails without title", %{scene: scene} do
      assert {:error, %Ash.Error.Invalid{}} =
               Storybox.Stories.ScriptView
               |> Ash.Changeset.for_create(:create, %{scene_id: scene.id})
               |> Ash.create()
    end

    test "fails without scene_id" do
      assert {:error, %Ash.Error.Invalid{}} =
               Storybox.Stories.ScriptView
               |> Ash.Changeset.for_create(:create, %{title: "Test"})
               |> Ash.create()
    end
  end

  describe "approve_version action" do
    test "sets approved_version_id on the view", %{scene: scene} do
      {:ok, view} =
        Storybox.Stories.ScriptView
        |> Ash.Changeset.for_create(:create, %{title: "Test Scene", scene_id: scene.id})
        |> Ash.create()

      {:ok, piece} =
        Storybox.Stories.ScriptPiece
        |> Ash.ActionInput.for_action(:create_version, %{
          scene_id: scene.id,
          content: "Approved content"
        })
        |> Ash.run_action()

      assert {:ok, updated_view} =
               view
               |> Ash.Changeset.for_update(:approve_version, %{version_id: piece.id})
               |> Ash.update()

      assert updated_view.approved_version_id == piece.id
    end
  end

  describe "read" do
    test "returns all script_views", %{scene: scene} do
      {:ok, view1} =
        Storybox.Stories.ScriptView
        |> Ash.Changeset.for_create(:create, %{title: "Scene 1", scene_id: scene.id})
        |> Ash.create()

      {:ok, view2} =
        Storybox.Stories.ScriptView
        |> Ash.Changeset.for_create(:create, %{title: "Scene 2", scene_id: scene.id})
        |> Ash.create()

      assert {:ok, views} = Storybox.Stories.ScriptView |> Ash.read()
      ids = Enum.map(views, & &1.id)
      assert view1.id in ids
      assert view2.id in ids
    end
  end
end
