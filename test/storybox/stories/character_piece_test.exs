defmodule Storybox.Stories.CharacterPieceTest do
  use Storybox.DataCase

  require Ash.Query

  setup do
    {:ok, user} =
      Storybox.Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "cp_test@example.com",
        password: "password123!",
        password_confirmation: "password123!"
      })
      |> Ash.create()

    {:ok, story} =
      Storybox.Stories.Story
      |> Ash.Changeset.for_create(:create, %{title: "Test Story", user_id: user.id})
      |> Ash.create()

    {:ok, character_a} =
      Storybox.Stories.Character
      |> Ash.Changeset.for_create(:create, %{name: "Alice", story_id: story.id})
      |> Ash.create()

    {:ok, character_b} =
      Storybox.Stories.Character
      |> Ash.Changeset.for_create(:create, %{name: "Bob", story_id: story.id})
      |> Ash.create()

    %{character_a: character_a, character_b: character_b}
  end

  describe "create" do
    test "persists character_id, content_uri, version_number", %{character_a: char} do
      uri = Storybox.Storage.uri_for_character_piece(char.id, 1)

      assert {:ok, piece} =
               Storybox.Stories.CharacterPiece
               |> Ash.Changeset.for_create(:create, %{
                 character_id: char.id,
                 content_uri: uri,
                 version_number: 1
               })
               |> Ash.create()

      assert piece.character_id == char.id
      assert piece.content_uri == uri
      assert piece.version_number == 1
    end

    test "fails without character_id" do
      assert {:error, %Ash.Error.Invalid{}} =
               Storybox.Stories.CharacterPiece
               |> Ash.Changeset.for_create(:create, %{
                 content_uri: "storybox://characters/x/v1",
                 version_number: 1
               })
               |> Ash.create()
    end

    test "rejects duplicate (character_id, version_number)", %{character_a: char} do
      uri = Storybox.Storage.uri_for_character_piece(char.id, 1)

      {:ok, _} =
        Storybox.Stories.CharacterPiece
        |> Ash.Changeset.for_create(:create, %{
          character_id: char.id,
          content_uri: uri,
          version_number: 1
        })
        |> Ash.create()

      assert {:error, %Ash.Error.Invalid{}} =
               Storybox.Stories.CharacterPiece
               |> Ash.Changeset.for_create(:create, %{
                 character_id: char.id,
                 content_uri: uri,
                 version_number: 1
               })
               |> Ash.create()
    end
  end

  describe "create_version action" do
    test "returns v1 with correct URI for first call", %{character_a: char} do
      assert {:ok, piece} =
               Storybox.Stories.CharacterPiece
               |> Ash.ActionInput.for_action(:create_version, %{
                 character_id: char.id,
                 content: "Essence: The hero."
               })
               |> Ash.run_action()

      assert piece.version_number == 1
      assert piece.character_id == char.id
      assert piece.content_uri == Storybox.Storage.uri_for_character_piece(char.id, 1)
    end

    test "second call returns v2 scoped to the same character", %{character_a: char} do
      {:ok, _v1} =
        Storybox.Stories.CharacterPiece
        |> Ash.ActionInput.for_action(:create_version, %{
          character_id: char.id,
          content: "Version one."
        })
        |> Ash.run_action()

      assert {:ok, v2} =
               Storybox.Stories.CharacterPiece
               |> Ash.ActionInput.for_action(:create_version, %{
                 character_id: char.id,
                 content: "Version two."
               })
               |> Ash.run_action()

      assert v2.version_number == 2
    end

    test "counter is independent per character", %{character_a: char_a, character_b: char_b} do
      {:ok, _} =
        Storybox.Stories.CharacterPiece
        |> Ash.ActionInput.for_action(:create_version, %{
          character_id: char_a.id,
          content: "Alice v1."
        })
        |> Ash.run_action()

      {:ok, _} =
        Storybox.Stories.CharacterPiece
        |> Ash.ActionInput.for_action(:create_version, %{
          character_id: char_a.id,
          content: "Alice v2."
        })
        |> Ash.run_action()

      assert {:ok, bob_v1} =
               Storybox.Stories.CharacterPiece
               |> Ash.ActionInput.for_action(:create_version, %{
                 character_id: char_b.id,
                 content: "Bob v1."
               })
               |> Ash.run_action()

      assert bob_v1.version_number == 1
      assert bob_v1.character_id == char_b.id
    end
  end
end
