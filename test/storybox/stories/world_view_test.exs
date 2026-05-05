defmodule Storybox.Stories.WorldViewTest do
  use Storybox.DataCase

  require Ash.Query

  setup do
    {:ok, user} =
      Storybox.Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "wv_test@example.com",
        password: "password123!",
        password_confirmation: "password123!"
      })
      |> Ash.create()

    {:ok, story} =
      Storybox.Stories.Story
      |> Ash.Changeset.for_create(:create, %{title: "Test Story", user_id: user.id})
      |> Ash.create()

    {:ok, world} =
      Storybox.Stories.World
      |> Ash.Changeset.for_create(:create, %{story_id: story.id})
      |> Ash.create()

    %{world: world}
  end

  describe "ensure_for_world" do
    test "creates a WorldView on first call", %{world: world} do
      assert {:ok, wv} =
               Storybox.Stories.WorldView
               |> Ash.ActionInput.for_action(:ensure_for_world, %{world_id: world.id})
               |> Ash.run_action()

      assert wv.world_id == world.id
    end

    test "is idempotent — second call returns the same record", %{world: world} do
      {:ok, wv1} =
        Storybox.Stories.WorldView
        |> Ash.ActionInput.for_action(:ensure_for_world, %{world_id: world.id})
        |> Ash.run_action()

      {:ok, wv2} =
        Storybox.Stories.WorldView
        |> Ash.ActionInput.for_action(:ensure_for_world, %{world_id: world.id})
        |> Ash.run_action()

      assert wv1.id == wv2.id
    end
  end

  describe "direct create" do
    test "succeeds with a unique world_id", %{world: world} do
      assert {:ok, wv} =
               Storybox.Stories.WorldView
               |> Ash.Changeset.for_create(:create, %{world_id: world.id})
               |> Ash.create()

      assert wv.world_id == world.id
    end

    test "raises unique-constraint error on duplicate world_id", %{world: world} do
      {:ok, _} =
        Storybox.Stories.WorldView
        |> Ash.Changeset.for_create(:create, %{world_id: world.id})
        |> Ash.create()

      assert {:error, %Ash.Error.Invalid{}} =
               Storybox.Stories.WorldView
               |> Ash.Changeset.for_create(:create, %{world_id: world.id})
               |> Ash.create()
    end
  end
end
