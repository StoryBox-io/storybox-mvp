defmodule Storybox.Stories.StoryTest do
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

    %{user: user}
  end

  describe "create" do
    test "creates a story with title and user_id, defaulting through_lines", %{user: user} do
      assert {:ok, story} =
               Storybox.Stories.Story
               |> Ash.Changeset.for_create(:create, %{title: "My Story", user_id: user.id})
               |> Ash.create()

      assert story.title == "My Story"
      assert story.user_id == user.id
      assert story.through_lines == ["preference"]
    end

    test "fails without a title", %{user: user} do
      assert {:error, %Ash.Error.Invalid{}} =
               Storybox.Stories.Story
               |> Ash.Changeset.for_create(:create, %{user_id: user.id})
               |> Ash.create()
    end

    test "fails without a user_id" do
      assert {:error, %Ash.Error.Invalid{}} =
               Storybox.Stories.Story
               |> Ash.Changeset.for_create(:create, %{title: "No User Story"})
               |> Ash.create()
    end
  end

  describe "read" do
    test "returns created stories", %{user: user} do
      {:ok, _story} =
        Storybox.Stories.Story
        |> Ash.Changeset.for_create(:create, %{title: "Readable Story", user_id: user.id})
        |> Ash.create()

      assert {:ok, stories} = Storybox.Stories.Story |> Ash.read()
      assert Enum.any?(stories, &(&1.title == "Readable Story"))
    end
  end

  describe "update" do
    test "changes the title", %{user: user} do
      {:ok, story} =
        Storybox.Stories.Story
        |> Ash.Changeset.for_create(:create, %{title: "Original Title", user_id: user.id})
        |> Ash.create()

      assert {:ok, updated} =
               story
               |> Ash.Changeset.for_update(:update, %{title: "Updated Title"})
               |> Ash.update()

      assert updated.title == "Updated Title"
    end
  end
end
