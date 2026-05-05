defmodule Storybox.Stories.WorldTest do
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
    test "creates a world with story_id", %{story: story} do
      assert {:ok, world} =
               Storybox.Stories.World
               |> Ash.Changeset.for_create(:create, %{story_id: story.id})
               |> Ash.create()

      assert world.story_id == story.id
    end

    test "fails without a story_id" do
      assert {:error, %Ash.Error.Invalid{}} =
               Storybox.Stories.World
               |> Ash.Changeset.for_create(:create, %{})
               |> Ash.create()
    end
  end

  describe "read" do
    test "returns created worlds", %{story: story} do
      {:ok, _} =
        Storybox.Stories.World
        |> Ash.Changeset.for_create(:create, %{story_id: story.id})
        |> Ash.create()

      assert {:ok, worlds} = Storybox.Stories.World |> Ash.read()
      assert Enum.any?(worlds, &(&1.story_id == story.id))
    end
  end

  describe "has_one :world_view association" do
    test "loads the WorldView after it is created", %{story: story} do
      {:ok, world} =
        Storybox.Stories.World
        |> Ash.Changeset.for_create(:create, %{story_id: story.id})
        |> Ash.create()

      {:ok, _wv} =
        Storybox.Stories.WorldView
        |> Ash.ActionInput.for_action(:ensure_for_world, %{world_id: world.id})
        |> Ash.run_action()

      {:ok, loaded} = Ash.load(world, :world_view)
      assert loaded.world_view != nil
      assert loaded.world_view.world_id == world.id
    end
  end

  describe "resource shape" do
    test "has no history, rules, or subtext attribute" do
      attrs = Ash.Resource.Info.attributes(Storybox.Stories.World)
      names = Enum.map(attrs, & &1.name)
      refute :history in names
      refute :rules in names
      refute :subtext in names
    end
  end
end
