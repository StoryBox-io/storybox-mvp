defmodule Storybox.Stories.CharacterTest do
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
    test "creates a character with name and story_id", %{story: story} do
      assert {:ok, character} =
               Storybox.Stories.Character
               |> Ash.Changeset.for_create(:create, %{
                 name: "Alice",
                 essence: "Driven by justice",
                 contradictions: ["brave", "reckless"],
                 voice: "Clipped, precise",
                 story_id: story.id
               })
               |> Ash.create()

      assert character.name == "Alice"
      assert character.essence == "Driven by justice"
      assert character.contradictions == ["brave", "reckless"]
      assert character.voice == "Clipped, precise"
      assert character.story_id == story.id
    end

    test "fails without a name", %{story: story} do
      assert {:error, %Ash.Error.Invalid{}} =
               Storybox.Stories.Character
               |> Ash.Changeset.for_create(:create, %{story_id: story.id})
               |> Ash.create()
    end

    test "fails without a story_id" do
      assert {:error, %Ash.Error.Invalid{}} =
               Storybox.Stories.Character
               |> Ash.Changeset.for_create(:create, %{name: "No Story"})
               |> Ash.create()
    end
  end

  describe "read" do
    test "returns created characters", %{story: story} do
      {:ok, _} =
        Storybox.Stories.Character
        |> Ash.Changeset.for_create(:create, %{name: "Bob", story_id: story.id})
        |> Ash.create()

      assert {:ok, characters} = Storybox.Stories.Character |> Ash.read()
      assert Enum.any?(characters, &(&1.name == "Bob"))
    end
  end

  describe "update" do
    test "changes character fields", %{story: story} do
      {:ok, character} =
        Storybox.Stories.Character
        |> Ash.Changeset.for_create(:create, %{name: "Charlie", story_id: story.id})
        |> Ash.create()

      assert {:ok, updated} =
               character
               |> Ash.Changeset.for_update(:update, %{name: "Charles", voice: "Deep baritone"})
               |> Ash.update()

      assert updated.name == "Charles"
      assert updated.voice == "Deep baritone"
    end
  end
end
