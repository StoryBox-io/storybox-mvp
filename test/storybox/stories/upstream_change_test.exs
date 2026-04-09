defmodule Storybox.Stories.UpstreamChangeTest do
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

    {:ok, sequence} =
      Storybox.Stories.SequencePiece
      |> Ash.Changeset.for_create(:create, %{
        title: "Act 1",
        position: 1,
        story_id: story.id
      })
      |> Ash.create()

    {:ok, sequence_version} =
      Storybox.Stories.SequenceVersion
      |> Ash.Changeset.for_create(:create, %{
        sequence_piece_id: sequence.id,
        content_uri: "storybox://stories/#{story.id}/sequences/#{sequence.id}/v1",
        version_number: 1
      })
      |> Ash.create()

    {:ok, scene} =
      Storybox.Stories.ScenePiece
      |> Ash.Changeset.for_create(:create, %{
        title: "Scene 1",
        position: 1,
        sequence_piece_id: sequence.id
      })
      |> Ash.create()

    {:ok, scene_version} =
      Storybox.Stories.SceneVersion
      |> Ash.Changeset.for_create(:create, %{
        scene_piece_id: scene.id,
        content_uri: "storybox://stories/#{story.id}/scenes/#{scene.id}/v1",
        version_number: 1
      })
      |> Ash.create()

    %{
      story: story,
      sequence_version: sequence_version,
      scene_version: scene_version
    }
  end

  describe "create" do
    test "creates an UpstreamChange for a sequence_version target", %{
      story: story,
      sequence_version: sequence_version
    } do
      assert {:ok, change} =
               Storybox.Stories.UpstreamChange
               |> Ash.Changeset.for_create(:create, %{
                 piece_version_type: :sequence_version,
                 piece_version_id: sequence_version.id,
                 component_type: :story,
                 component_id: story.id,
                 version_before: "2026-01-01T00:00:00Z",
                 version_after: "2026-02-01T00:00:00Z"
               })
               |> Ash.create()

      assert change.piece_version_type == :sequence_version
      assert change.piece_version_id == sequence_version.id
      assert change.component_type == :story
      assert change.component_id == story.id
      assert change.version_before == "2026-01-01T00:00:00Z"
      assert change.version_after == "2026-02-01T00:00:00Z"
      assert change.acknowledged == false
    end

    test "creates an UpstreamChange for a scene_version target", %{
      story: story,
      scene_version: scene_version
    } do
      assert {:ok, change} =
               Storybox.Stories.UpstreamChange
               |> Ash.Changeset.for_create(:create, %{
                 piece_version_type: :scene_version,
                 piece_version_id: scene_version.id,
                 component_type: :character,
                 component_id: story.id
               })
               |> Ash.create()

      assert change.piece_version_type == :scene_version
      assert change.component_type == :character
      assert change.acknowledged == false
      assert is_nil(change.version_before)
      assert is_nil(change.version_after)
    end

    test "defaults acknowledged to false", %{story: story, scene_version: scene_version} do
      assert {:ok, change} =
               Storybox.Stories.UpstreamChange
               |> Ash.Changeset.for_create(:create, %{
                 piece_version_type: :scene_version,
                 piece_version_id: scene_version.id,
                 component_type: :world,
                 component_id: story.id
               })
               |> Ash.create()

      assert change.acknowledged == false
    end

    test "fails with invalid piece_version_type", %{story: story, scene_version: scene_version} do
      assert {:error, %Ash.Error.Invalid{}} =
               Storybox.Stories.UpstreamChange
               |> Ash.Changeset.for_create(:create, %{
                 piece_version_type: :bad_type,
                 piece_version_id: scene_version.id,
                 component_type: :story,
                 component_id: story.id
               })
               |> Ash.create()
    end

    test "fails with invalid component_type", %{story: story, scene_version: scene_version} do
      assert {:error, %Ash.Error.Invalid{}} =
               Storybox.Stories.UpstreamChange
               |> Ash.Changeset.for_create(:create, %{
                 piece_version_type: :scene_version,
                 piece_version_id: scene_version.id,
                 component_type: :invalid,
                 component_id: story.id
               })
               |> Ash.create()
    end

    test "fails without required fields" do
      assert {:error, %Ash.Error.Invalid{}} =
               Storybox.Stories.UpstreamChange
               |> Ash.Changeset.for_create(:create, %{})
               |> Ash.create()
    end
  end

  describe "acknowledge" do
    test "sets acknowledged to true", %{story: story, scene_version: scene_version} do
      {:ok, change} =
        Storybox.Stories.UpstreamChange
        |> Ash.Changeset.for_create(:create, %{
          piece_version_type: :scene_version,
          piece_version_id: scene_version.id,
          component_type: :story,
          component_id: story.id
        })
        |> Ash.create()

      assert {:ok, acknowledged} =
               change
               |> Ash.Changeset.for_update(:acknowledge, %{})
               |> Ash.update()

      assert acknowledged.acknowledged == true
    end
  end

  describe "read" do
    test "filters by component_type", %{story: story, scene_version: scene_version} do
      {:ok, _} =
        Storybox.Stories.UpstreamChange
        |> Ash.Changeset.for_create(:create, %{
          piece_version_type: :scene_version,
          piece_version_id: scene_version.id,
          component_type: :story,
          component_id: story.id
        })
        |> Ash.create()

      {:ok, _} =
        Storybox.Stories.UpstreamChange
        |> Ash.Changeset.for_create(:create, %{
          piece_version_type: :scene_version,
          piece_version_id: scene_version.id,
          component_type: :character,
          component_id: story.id
        })
        |> Ash.create()

      require Ash.Query

      assert {:ok, results} =
               Storybox.Stories.UpstreamChange
               |> Ash.Query.filter(component_type == :story)
               |> Ash.read()

      assert length(results) == 1
      assert hd(results).component_type == :story
    end
  end
end
