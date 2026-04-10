defmodule Storybox.Stories.SynopsisVersionTest do
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
    test "creates a synopsis version with all required fields", %{story: story} do
      assert {:ok, version} =
               Storybox.Stories.SynopsisVersion
               |> Ash.Changeset.for_create(:create, %{
                 story_id: story.id,
                 content_uri: "storybox://stories/#{story.id}/synopsis/v1",
                 version_number: 1
               })
               |> Ash.create()

      assert version.story_id == story.id
      assert version.content_uri == "storybox://stories/#{story.id}/synopsis/v1"
      assert version.version_number == 1
    end

    test "creates multiple versions for the same story (append-only)", %{story: story} do
      {:ok, _v1} =
        Storybox.Stories.SynopsisVersion
        |> Ash.Changeset.for_create(:create, %{
          story_id: story.id,
          content_uri: "storybox://stories/#{story.id}/synopsis/v1",
          version_number: 1
        })
        |> Ash.create()

      {:ok, _v2} =
        Storybox.Stories.SynopsisVersion
        |> Ash.Changeset.for_create(:create, %{
          story_id: story.id,
          content_uri: "storybox://stories/#{story.id}/synopsis/v2",
          version_number: 2
        })
        |> Ash.create()

      assert {:ok, versions} = Storybox.Stories.SynopsisVersion |> Ash.read()
      version_numbers = Enum.map(versions, & &1.version_number)
      assert 1 in version_numbers
      assert 2 in version_numbers
    end

    test "fails without story_id" do
      assert {:error, %Ash.Error.Invalid{}} =
               Storybox.Stories.SynopsisVersion
               |> Ash.Changeset.for_create(:create, %{
                 content_uri: "storybox://stories/123/synopsis/v1",
                 version_number: 1
               })
               |> Ash.create()
    end

    test "fails without content_uri", %{story: story} do
      assert {:error, %Ash.Error.Invalid{}} =
               Storybox.Stories.SynopsisVersion
               |> Ash.Changeset.for_create(:create, %{
                 story_id: story.id,
                 version_number: 1
               })
               |> Ash.create()
    end

    test "fails without version_number", %{story: story} do
      assert {:error, %Ash.Error.Invalid{}} =
               Storybox.Stories.SynopsisVersion
               |> Ash.Changeset.for_create(:create, %{
                 story_id: story.id,
                 content_uri: "storybox://stories/#{story.id}/synopsis/v1"
               })
               |> Ash.create()
    end
  end

  describe "read" do
    test "returns created synopsis versions", %{story: story} do
      {:ok, version} =
        Storybox.Stories.SynopsisVersion
        |> Ash.Changeset.for_create(:create, %{
          story_id: story.id,
          content_uri: "storybox://stories/#{story.id}/synopsis/v1",
          version_number: 1
        })
        |> Ash.create()

      assert {:ok, versions} = Storybox.Stories.SynopsisVersion |> Ash.read()
      assert Enum.any?(versions, &(&1.id == version.id))
    end
  end

  describe "create_version action" do
    test "creates first version with version_number 1 and correct URI", %{story: story} do
      assert {:ok, version} =
               Storybox.Stories.SynopsisVersion
               |> Ash.ActionInput.for_action(:create_version, %{
                 story_id: story.id,
                 content: "A detective story about memory."
               })
               |> Ash.run_action()

      assert version.story_id == story.id
      assert version.version_number == 1
      assert version.content_uri == Storybox.Storage.uri_for_synopsis(story.id, 1)
    end

    test "increments version_number for subsequent versions", %{story: story} do
      {:ok, _v1} =
        Storybox.Stories.SynopsisVersion
        |> Ash.ActionInput.for_action(:create_version, %{
          story_id: story.id,
          content: "First synopsis draft."
        })
        |> Ash.run_action()

      assert {:ok, v2} =
               Storybox.Stories.SynopsisVersion
               |> Ash.ActionInput.for_action(:create_version, %{
                 story_id: story.id,
                 content: "Second synopsis draft."
               })
               |> Ash.run_action()

      assert v2.version_number == 2
    end
  end
end
