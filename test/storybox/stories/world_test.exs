defmodule Storybox.Stories.WorldTest do
  use Storybox.DataCase

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
               |> Ash.Changeset.for_create(:create, %{
                 history: "Founded in 1842",
                 rules: "Magic costs memory",
                 subtext: "Power corrupts",
                 story_id: story.id
               })
               |> Ash.create()

      assert world.history == "Founded in 1842"
      assert world.rules == "Magic costs memory"
      assert world.subtext == "Power corrupts"
      assert world.story_id == story.id
    end

    test "creates a world with only story_id (all fields optional)", %{story: story} do
      assert {:ok, world} =
               Storybox.Stories.World
               |> Ash.Changeset.for_create(:create, %{story_id: story.id})
               |> Ash.create()

      assert world.story_id == story.id
      assert world.history == nil
    end

    test "fails without a story_id" do
      assert {:error, %Ash.Error.Invalid{}} =
               Storybox.Stories.World
               |> Ash.Changeset.for_create(:create, %{history: "No story"})
               |> Ash.create()
    end
  end

  describe "read" do
    test "returns created worlds", %{story: story} do
      {:ok, _} =
        Storybox.Stories.World
        |> Ash.Changeset.for_create(:create, %{history: "Ancient times", story_id: story.id})
        |> Ash.create()

      assert {:ok, worlds} = Storybox.Stories.World |> Ash.read()
      assert Enum.any?(worlds, &(&1.history == "Ancient times"))
    end
  end

  describe "update" do
    test "changes world fields", %{story: story} do
      {:ok, world} =
        Storybox.Stories.World
        |> Ash.Changeset.for_create(:create, %{history: "Old history", story_id: story.id})
        |> Ash.create()

      assert {:ok, updated} =
               world
               |> Ash.Changeset.for_update(:update, %{
                 history: "New history",
                 subtext: "Decay is inevitable"
               })
               |> Ash.update()

      assert updated.history == "New history"
      assert updated.subtext == "Decay is inevitable"
    end
  end
end
