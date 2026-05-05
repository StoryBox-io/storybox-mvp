defmodule Storybox.Stories.WorldPieceTest do
  use Storybox.DataCase

  require Ash.Query

  setup do
    {:ok, user} =
      Storybox.Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "wp_test@example.com",
        password: "password123!",
        password_confirmation: "password123!"
      })
      |> Ash.create()

    {:ok, story_a} =
      Storybox.Stories.Story
      |> Ash.Changeset.for_create(:create, %{title: "Story A", user_id: user.id})
      |> Ash.create()

    {:ok, story_b} =
      Storybox.Stories.Story
      |> Ash.Changeset.for_create(:create, %{title: "Story B", user_id: user.id})
      |> Ash.create()

    {:ok, world_a} =
      Storybox.Stories.World
      |> Ash.Changeset.for_create(:create, %{story_id: story_a.id})
      |> Ash.create()

    {:ok, world_b} =
      Storybox.Stories.World
      |> Ash.Changeset.for_create(:create, %{story_id: story_b.id})
      |> Ash.create()

    %{world_a: world_a, world_b: world_b}
  end

  describe "create" do
    test "persists world_id, content_uri, version_number", %{world_a: world} do
      uri = Storybox.Storage.uri_for_world_piece(world.id, 1)

      assert {:ok, piece} =
               Storybox.Stories.WorldPiece
               |> Ash.Changeset.for_create(:create, %{
                 world_id: world.id,
                 content_uri: uri,
                 version_number: 1
               })
               |> Ash.create()

      assert piece.world_id == world.id
      assert piece.content_uri == uri
      assert piece.version_number == 1
    end

    test "fails without world_id" do
      assert {:error, %Ash.Error.Invalid{}} =
               Storybox.Stories.WorldPiece
               |> Ash.Changeset.for_create(:create, %{
                 content_uri: "storybox://worlds/x/v1",
                 version_number: 1
               })
               |> Ash.create()
    end

    test "rejects duplicate (world_id, version_number)", %{world_a: world} do
      uri = Storybox.Storage.uri_for_world_piece(world.id, 1)

      {:ok, _} =
        Storybox.Stories.WorldPiece
        |> Ash.Changeset.for_create(:create, %{
          world_id: world.id,
          content_uri: uri,
          version_number: 1
        })
        |> Ash.create()

      assert {:error, %Ash.Error.Invalid{}} =
               Storybox.Stories.WorldPiece
               |> Ash.Changeset.for_create(:create, %{
                 world_id: world.id,
                 content_uri: uri,
                 version_number: 1
               })
               |> Ash.create()
    end
  end

  describe "create_version action" do
    test "returns v1 with correct URI for first call", %{world_a: world} do
      assert {:ok, piece} =
               Storybox.Stories.WorldPiece
               |> Ash.ActionInput.for_action(:create_version, %{
                 world_id: world.id,
                 content: "History: Ancient times."
               })
               |> Ash.run_action()

      assert piece.version_number == 1
      assert piece.world_id == world.id
      assert piece.content_uri == Storybox.Storage.uri_for_world_piece(world.id, 1)
    end

    test "second call returns v2", %{world_a: world} do
      {:ok, _v1} =
        Storybox.Stories.WorldPiece
        |> Ash.ActionInput.for_action(:create_version, %{
          world_id: world.id,
          content: "Version one."
        })
        |> Ash.run_action()

      assert {:ok, v2} =
               Storybox.Stories.WorldPiece
               |> Ash.ActionInput.for_action(:create_version, %{
                 world_id: world.id,
                 content: "Version two."
               })
               |> Ash.run_action()

      assert v2.version_number == 2
    end

    test "counter is independent per world", %{world_a: world_a, world_b: world_b} do
      {:ok, _} =
        Storybox.Stories.WorldPiece
        |> Ash.ActionInput.for_action(:create_version, %{
          world_id: world_a.id,
          content: "World A v1."
        })
        |> Ash.run_action()

      {:ok, _} =
        Storybox.Stories.WorldPiece
        |> Ash.ActionInput.for_action(:create_version, %{
          world_id: world_a.id,
          content: "World A v2."
        })
        |> Ash.run_action()

      assert {:ok, b_v1} =
               Storybox.Stories.WorldPiece
               |> Ash.ActionInput.for_action(:create_version, %{
                 world_id: world_b.id,
                 content: "World B v1."
               })
               |> Ash.run_action()

      assert b_v1.version_number == 1
      assert b_v1.world_id == world_b.id
    end
  end
end
