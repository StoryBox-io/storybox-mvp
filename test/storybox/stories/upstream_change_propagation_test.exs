defmodule Storybox.Stories.UpstreamChangePropagationTest do
  use Storybox.DataCase

  require Ash.Query

  alias Storybox.Stories.{
    Character,
    Scene,
    ScriptPiece,
    Story,
    UpstreamChange,
    World
  }

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
      Story
      |> Ash.Changeset.for_create(:create, %{title: "Test Story", user_id: user.id})
      |> Ash.create()

    {:ok, character} =
      Character
      |> Ash.Changeset.for_create(:create, %{name: "Hero", story_id: story.id})
      |> Ash.create()

    {:ok, world} =
      World
      |> Ash.Changeset.for_create(:create, %{history: "Ancient times", story_id: story.id})
      |> Ash.create()

    {:ok, scene} =
      Scene
      |> Ash.Changeset.for_create(:create, %{title: "Scene 1", story_id: story.id})
      |> Ash.create()

    {:ok, script_piece} =
      ScriptPiece
      |> Ash.Changeset.for_create(:create, %{
        scene_id: scene.id,
        content_uri: Storybox.Storage.uri_for_script_piece(scene.id, 1),
        version_number: 1
      })
      |> Ash.create()

    %{
      story: story,
      character: character,
      world: world,
      script_piece: script_piece
    }
  end

  describe "story update propagation" do
    test "creates UpstreamChange for script_piece with component_type :story", %{
      story: story,
      script_piece: sp
    } do
      story
      |> Ash.Changeset.for_update(:update, %{logline: "New logline"})
      |> Ash.update!()

      assert {:ok, [change]} =
               UpstreamChange
               |> Ash.Query.filter(
                 piece_version_type == :script_piece and piece_version_id == ^sp.id
               )
               |> Ash.read()

      assert change.component_type == :story
      assert change.component_id == story.id
      assert change.acknowledged == false
      assert is_binary(change.version_before)
      assert is_binary(change.version_after)
      assert change.version_before != change.version_after
    end
  end

  describe "character update propagation" do
    test "creates UpstreamChange with component_type :character", %{
      character: character,
      script_piece: sp
    } do
      character
      |> Ash.Changeset.for_update(:update, %{essence: "Brave"})
      |> Ash.update!()

      assert {:ok, [change]} =
               UpstreamChange
               |> Ash.Query.filter(
                 piece_version_type == :script_piece and piece_version_id == ^sp.id
               )
               |> Ash.read()

      assert change.component_type == :character
      assert change.component_id == character.id
    end
  end

  describe "world update propagation" do
    test "creates UpstreamChange with component_type :world", %{
      world: world,
      script_piece: sp
    } do
      world
      |> Ash.Changeset.for_update(:update, %{rules: "Magic is real"})
      |> Ash.update!()

      assert {:ok, [change]} =
               UpstreamChange
               |> Ash.Query.filter(
                 piece_version_type == :script_piece and piece_version_id == ^sp.id
               )
               |> Ash.read()

      assert change.component_type == :world
      assert change.component_id == world.id
    end
  end

  describe "no propagation on create" do
    test "creating a story does not create UpstreamChange records", %{story: story} do
      assert {:ok, changes} =
               UpstreamChange
               |> Ash.Query.filter(component_type == :story and component_id == ^story.id)
               |> Ash.read()

      assert changes == []
    end
  end
end
