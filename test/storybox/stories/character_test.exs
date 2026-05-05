defmodule Storybox.Stories.CharacterTest do
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
    test "creates a character with name and story_id", %{story: story} do
      assert {:ok, character} =
               Storybox.Stories.Character
               |> Ash.Changeset.for_create(:create, %{
                 name: "Alice",
                 story_id: story.id
               })
               |> Ash.create()

      assert character.name == "Alice"
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
    test "changes character name", %{story: story} do
      {:ok, character} =
        Storybox.Stories.Character
        |> Ash.Changeset.for_create(:create, %{name: "Charlie", story_id: story.id})
        |> Ash.create()

      assert {:ok, updated} =
               character
               |> Ash.Changeset.for_update(:update, %{name: "Charles"})
               |> Ash.update()

      assert updated.name == "Charles"
    end
  end

  describe "has_many :character_pieces association" do
    test "returns CharacterPieces scoped to the Character", %{story: story} do
      {:ok, character} =
        Storybox.Stories.Character
        |> Ash.Changeset.for_create(:create, %{name: "Dana", story_id: story.id})
        |> Ash.create()

      {:ok, _piece} =
        Storybox.Stories.CharacterPiece
        |> Ash.ActionInput.for_action(:create_version, %{
          character_id: character.id,
          content: "Essence: Brave."
        })
        |> Ash.run_action()

      {:ok, loaded} = Ash.load(character, :character_pieces)
      assert length(loaded.character_pieces) == 1
      assert hd(loaded.character_pieces).character_id == character.id
    end
  end

  describe "resource shape" do
    test "has no essence, voice, or contradictions attribute" do
      attrs = Ash.Resource.Info.attributes(Storybox.Stories.Character)
      names = Enum.map(attrs, & &1.name)
      refute :essence in names
      refute :voice in names
      refute :contradictions in names
    end
  end
end
