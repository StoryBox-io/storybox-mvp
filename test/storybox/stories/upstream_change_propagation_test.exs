defmodule Storybox.Stories.UpstreamChangePropagationTest do
  use Storybox.DataCase

  require Ash.Query

  alias Storybox.Stories.{
    Character,
    ScenePiece,
    SceneVersion,
    SequencePiece,
    SequenceVersion,
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

    {:ok, sequence} =
      SequencePiece
      |> Ash.Changeset.for_create(:create, %{title: "Act 1", position: 1, story_id: story.id})
      |> Ash.create()

    {:ok, sequence_version} =
      SequenceVersion
      |> Ash.Changeset.for_create(:create, %{
        sequence_piece_id: sequence.id,
        content_uri: "storybox://stories/#{story.id}/sequences/#{sequence.id}/v1",
        version_number: 1
      })
      |> Ash.create()

    {:ok, scene} =
      ScenePiece
      |> Ash.Changeset.for_create(:create, %{
        title: "Scene 1",
        position: 1,
        sequence_piece_id: sequence.id
      })
      |> Ash.create()

    {:ok, scene_version} =
      SceneVersion
      |> Ash.Changeset.for_create(:create, %{
        scene_piece_id: scene.id,
        content_uri: "storybox://stories/#{story.id}/scenes/#{scene.id}/v1",
        version_number: 1
      })
      |> Ash.create()

    %{
      story: story,
      character: character,
      world: world,
      sequence_version: sequence_version,
      scene_version: scene_version
    }
  end

  describe "story update propagation" do
    test "marks all sequence_versions stale", %{story: story, sequence_version: sv} do
      assert sv.upstream_status == :current

      story
      |> Ash.Changeset.for_update(:update, %{title: "Updated Title"})
      |> Ash.update!()

      updated = Ash.get!(SequenceVersion, sv.id)
      assert updated.upstream_status == :stale
    end

    test "marks all scene_versions stale", %{story: story, scene_version: sv} do
      assert sv.upstream_status == :current

      story
      |> Ash.Changeset.for_update(:update, %{title: "Updated Title"})
      |> Ash.update!()

      updated = Ash.get!(SceneVersion, sv.id)
      assert updated.upstream_status == :stale
    end

    test "creates UpstreamChange for sequence_version with component_type :story", %{
      story: story,
      sequence_version: sv
    } do
      story
      |> Ash.Changeset.for_update(:update, %{logline: "New logline"})
      |> Ash.update!()

      assert {:ok, [change]} =
               UpstreamChange
               |> Ash.Query.filter(
                 piece_version_type == :sequence_version and piece_version_id == ^sv.id
               )
               |> Ash.read()

      assert change.component_type == :story
      assert change.component_id == story.id
      assert change.acknowledged == false
      assert is_binary(change.version_before)
      assert is_binary(change.version_after)
      assert change.version_before != change.version_after
    end

    test "creates UpstreamChange for scene_version with component_type :story", %{
      story: story,
      scene_version: sv
    } do
      story
      |> Ash.Changeset.for_update(:update, %{logline: "New logline"})
      |> Ash.update!()

      assert {:ok, [change]} =
               UpstreamChange
               |> Ash.Query.filter(
                 piece_version_type == :scene_version and piece_version_id == ^sv.id
               )
               |> Ash.read()

      assert change.component_type == :story
      assert change.component_id == story.id
    end
  end

  describe "character update propagation" do
    test "marks sequence_versions stale", %{character: character, sequence_version: sv} do
      character
      |> Ash.Changeset.for_update(:update, %{essence: "Brave"})
      |> Ash.update!()

      updated = Ash.get!(SequenceVersion, sv.id)
      assert updated.upstream_status == :stale
    end

    test "marks scene_versions stale", %{character: character, scene_version: sv} do
      character
      |> Ash.Changeset.for_update(:update, %{essence: "Brave"})
      |> Ash.update!()

      updated = Ash.get!(SceneVersion, sv.id)
      assert updated.upstream_status == :stale
    end

    test "creates UpstreamChange with component_type :character", %{
      character: character,
      sequence_version: sv
    } do
      character
      |> Ash.Changeset.for_update(:update, %{essence: "Brave"})
      |> Ash.update!()

      assert {:ok, [change]} =
               UpstreamChange
               |> Ash.Query.filter(
                 piece_version_type == :sequence_version and piece_version_id == ^sv.id
               )
               |> Ash.read()

      assert change.component_type == :character
      assert change.component_id == character.id
    end
  end

  describe "world update propagation" do
    test "marks sequence_versions stale", %{world: world, sequence_version: sv} do
      world
      |> Ash.Changeset.for_update(:update, %{rules: "Magic is real"})
      |> Ash.update!()

      updated = Ash.get!(SequenceVersion, sv.id)
      assert updated.upstream_status == :stale
    end

    test "marks scene_versions stale", %{world: world, scene_version: sv} do
      world
      |> Ash.Changeset.for_update(:update, %{rules: "Magic is real"})
      |> Ash.update!()

      updated = Ash.get!(SceneVersion, sv.id)
      assert updated.upstream_status == :stale
    end

    test "creates UpstreamChange with component_type :world", %{
      world: world,
      scene_version: sv
    } do
      world
      |> Ash.Changeset.for_update(:update, %{rules: "Magic is real"})
      |> Ash.update!()

      assert {:ok, [change]} =
               UpstreamChange
               |> Ash.Query.filter(
                 piece_version_type == :scene_version and piece_version_id == ^sv.id
               )
               |> Ash.read()

      assert change.component_type == :world
      assert change.component_id == world.id
    end
  end

  describe "no propagation on create" do
    test "creating a story does not create UpstreamChange records", %{story: story} do
      # story was created in setup — confirm no changes were triggered
      assert {:ok, changes} =
               UpstreamChange
               |> Ash.Query.filter(component_type == :story and component_id == ^story.id)
               |> Ash.read()

      assert changes == []
    end
  end
end
