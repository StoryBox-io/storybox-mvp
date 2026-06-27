defmodule Storybox.Stories.SceneTest do
  use Storybox.DataCase

  import ExUnit.CaptureLog

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

  defp create_scene(attrs) do
    Storybox.Stories.Scene
    |> Ash.Changeset.for_create(:create, attrs)
    |> Ash.create()
  end

  describe "create" do
    test "auto-generates slug from slugline when slug omitted", %{story: story} do
      assert {:ok, scene} =
               create_scene(%{slugline: "EXT. CATHEDRAL - NIGHT", story_id: story.id})

      assert scene.slug == Slug.slugify("EXT. CATHEDRAL - NIGHT", separator: "_")
      assert scene.story_id == story.id
    end

    test "explicit slug wins over slugline", %{story: story} do
      assert {:ok, scene} =
               create_scene(%{
                 slugline: "EXT. CATHEDRAL - NIGHT",
                 slug: "the-argument",
                 story_id: story.id
               })

      assert scene.slug == "the-argument"
    end

    test "creates with explicit slug and no slugline", %{story: story} do
      assert {:ok, scene} = create_scene(%{slug: "opening", story_id: story.id})

      assert scene.slug == "opening"
    end

    test "fails without slug or slugline", %{story: story} do
      assert {:error, %Ash.Error.Invalid{}} = create_scene(%{story_id: story.id})
    end

    test "fails without story_id" do
      assert {:error, %Ash.Error.Invalid{}} = create_scene(%{slug: "orphan"})
    end

    test "rejects a duplicate slug within the same story", %{story: story} do
      assert {:ok, _} = create_scene(%{slug: "opening", story_id: story.id})

      assert {:error, %Ash.Error.Invalid{}} = create_scene(%{slug: "opening", story_id: story.id})
    end

    test "allows the same slug in different stories", %{story: story} do
      {:ok, user2} =
        Storybox.Accounts.User
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: "test2@example.com",
          password: "password123!",
          password_confirmation: "password123!"
        })
        |> Ash.create()

      {:ok, story2} =
        Storybox.Stories.Story
        |> Ash.Changeset.for_create(:create, %{title: "Other Story", user_id: user2.id})
        |> Ash.create()

      assert {:ok, _} = create_scene(%{slug: "opening", story_id: story.id})
      assert {:ok, _} = create_scene(%{slug: "opening", story_id: story2.id})
    end

    test "warns but succeeds when slug token collides with a character name", %{story: story} do
      {:ok, _character} =
        Storybox.Stories.Character
        |> Ash.Changeset.for_create(:create, %{name: "Kestrel", story_id: story.id})
        |> Ash.create()

      log =
        capture_log(fn ->
          assert {:ok, scene} = create_scene(%{slug: "ext_ruins_kestrel", story_id: story.id})
          assert scene.slug == "ext_ruins_kestrel"
        end)

      assert log =~ "collides with Character"
      assert log =~ "Kestrel"
    end

    test "does not warn when no character name matches the slug", %{story: story} do
      {:ok, _character} =
        Storybox.Stories.Character
        |> Ash.Changeset.for_create(:create, %{name: "Kestrel", story_id: story.id})
        |> Ash.create()

      log =
        capture_log(fn ->
          assert {:ok, _scene} = create_scene(%{slug: "ext_cottage_night", story_id: story.id})
        end)

      refute log =~ "collides with Character"
    end
  end

  describe "update" do
    test "updates slug", %{story: story} do
      {:ok, scene} = create_scene(%{slug: "original", story_id: story.id})

      assert {:ok, updated} =
               scene
               |> Ash.Changeset.for_update(:update, %{slug: "revised"})
               |> Ash.update()

      assert updated.slug == "revised"
    end

    test "rejects updating to a slug already used in the story", %{story: story} do
      {:ok, _first} = create_scene(%{slug: "taken", story_id: story.id})
      {:ok, scene} = create_scene(%{slug: "free", story_id: story.id})

      assert {:error, %Ash.Error.Invalid{}} =
               scene
               |> Ash.Changeset.for_update(:update, %{slug: "taken"})
               |> Ash.update()
    end
  end

  describe "destroy" do
    test "deletes a scene", %{story: story} do
      {:ok, scene} = create_scene(%{slug: "temp-scene", story_id: story.id})

      assert :ok = Ash.destroy(scene, authorize?: false)

      assert nil ==
               Storybox.Stories.Scene
               |> Ash.Query.filter(id == ^scene.id)
               |> Ash.read_one!(authorize?: false)
    end
  end

  describe "read" do
    test "returns scenes for a story", %{story: story} do
      {:ok, scene1} = create_scene(%{slug: "scene-a", story_id: story.id})
      {:ok, scene2} = create_scene(%{slug: "scene-b", story_id: story.id})

      assert {:ok, scenes} = Storybox.Stories.Scene |> Ash.read()
      ids = Enum.map(scenes, & &1.id)
      assert scene1.id in ids
      assert scene2.id in ids
    end
  end
end
