defmodule Storybox.Stories.SceneTest do
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

    %{story: story}
  end

  describe "create" do
    test "creates a scene with required fields", %{story: story} do
      assert {:ok, scene} =
               Storybox.Stories.Scene
               |> Ash.Changeset.for_create(:create, %{title: "Opening", story_id: story.id})
               |> Ash.create()

      assert scene.title == "Opening"
      assert scene.story_id == story.id
      assert is_nil(scene.slug)
    end

    test "creates a scene with optional slug", %{story: story} do
      assert {:ok, scene} =
               Storybox.Stories.Scene
               |> Ash.Changeset.for_create(:create, %{
                 title: "Opening",
                 slug: "opening",
                 story_id: story.id
               })
               |> Ash.create()

      assert scene.slug == "opening"
    end

    test "fails without title", %{story: story} do
      assert {:error, %Ash.Error.Invalid{}} =
               Storybox.Stories.Scene
               |> Ash.Changeset.for_create(:create, %{story_id: story.id})
               |> Ash.create()
    end

    test "fails without story_id" do
      assert {:error, %Ash.Error.Invalid{}} =
               Storybox.Stories.Scene
               |> Ash.Changeset.for_create(:create, %{title: "Test"})
               |> Ash.create()
    end
  end

  describe "update" do
    test "updates title and slug", %{story: story} do
      {:ok, scene} =
        Storybox.Stories.Scene
        |> Ash.Changeset.for_create(:create, %{title: "Original", story_id: story.id})
        |> Ash.create()

      assert {:ok, updated} =
               scene
               |> Ash.Changeset.for_update(:update, %{title: "Revised", slug: "revised"})
               |> Ash.update()

      assert updated.title == "Revised"
      assert updated.slug == "revised"
    end
  end

  describe "destroy" do
    test "deletes a scene", %{story: story} do
      {:ok, scene} =
        Storybox.Stories.Scene
        |> Ash.Changeset.for_create(:create, %{title: "Temp Scene", story_id: story.id})
        |> Ash.create()

      assert :ok = Ash.destroy(scene, authorize?: false)

      assert nil ==
               Storybox.Stories.Scene
               |> Ash.Query.filter(id == ^scene.id)
               |> Ash.read_one!(authorize?: false)
    end
  end

  describe "read" do
    test "returns scenes for a story", %{story: story} do
      {:ok, scene1} =
        Storybox.Stories.Scene
        |> Ash.Changeset.for_create(:create, %{title: "Scene A", story_id: story.id})
        |> Ash.create()

      {:ok, scene2} =
        Storybox.Stories.Scene
        |> Ash.Changeset.for_create(:create, %{title: "Scene B", story_id: story.id})
        |> Ash.create()

      assert {:ok, scenes} = Storybox.Stories.Scene |> Ash.read()
      ids = Enum.map(scenes, & &1.id)
      assert scene1.id in ids
      assert scene2.id in ids
    end
  end
end
