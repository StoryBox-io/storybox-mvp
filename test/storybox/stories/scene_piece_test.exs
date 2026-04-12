defmodule Storybox.Stories.ScenePieceTest do
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

    {:ok, sequence} =
      Storybox.Stories.SequencePiece
      |> Ash.Changeset.for_create(:create, %{
        title: "Act 1",
        position: 1,
        story_id: story.id
      })
      |> Ash.create()

    %{story: story, sequence: sequence}
  end

  describe "create scene_piece" do
    test "creates a scene_piece with required fields", %{sequence: sequence} do
      assert {:ok, piece} =
               Storybox.Stories.ScenePiece
               |> Ash.Changeset.for_create(:create, %{
                 title: "Opening Scene",
                 position: 1,
                 sequence_piece_id: sequence.id
               })
               |> Ash.create()

      assert piece.title == "Opening Scene"
      assert piece.position == 1
      assert piece.sequence_piece_id == sequence.id
      assert is_nil(piece.approved_version_id)
    end

    test "fails without title", %{sequence: sequence} do
      assert {:error, %Ash.Error.Invalid{}} =
               Storybox.Stories.ScenePiece
               |> Ash.Changeset.for_create(:create, %{
                 position: 1,
                 sequence_piece_id: sequence.id
               })
               |> Ash.create()
    end

    test "fails without sequence_piece_id" do
      assert {:error, %Ash.Error.Invalid{}} =
               Storybox.Stories.ScenePiece
               |> Ash.Changeset.for_create(:create, %{
                 title: "Test",
                 position: 1
               })
               |> Ash.create()
    end
  end

  describe "create_version action" do
    test "creates first version with version_number 1", %{story: story, sequence: sequence} do
      {:ok, piece} =
        Storybox.Stories.ScenePiece
        |> Ash.Changeset.for_create(:create, %{
          title: "Opening Scene",
          position: 1,
          sequence_piece_id: sequence.id
        })
        |> Ash.create()

      assert {:ok, version} =
               Storybox.Stories.ScenePiece
               |> Ash.ActionInput.for_action(:create_version, %{
                 scene_piece_id: piece.id,
                 content: "INT. COFFEE SHOP - DAY"
               })
               |> Ash.run_action()

      assert version.version_number == 1
      assert version.upstream_status == :current
      assert version.weights == %{}
      assert version.scene_piece_id == piece.id

      assert version.content_uri ==
               Storybox.Storage.uri_for_scene(story.id, piece.id, 1)
    end

    test "increments version_number for subsequent versions", %{sequence: sequence} do
      {:ok, piece} =
        Storybox.Stories.ScenePiece
        |> Ash.Changeset.for_create(:create, %{
          title: "Test Scene",
          position: 1,
          sequence_piece_id: sequence.id
        })
        |> Ash.create()

      {:ok, _version1} =
        Storybox.Stories.ScenePiece
        |> Ash.ActionInput.for_action(:create_version, %{
          scene_piece_id: piece.id,
          content: "Version one content"
        })
        |> Ash.run_action()

      assert {:ok, version2} =
               Storybox.Stories.ScenePiece
               |> Ash.ActionInput.for_action(:create_version, %{
                 scene_piece_id: piece.id,
                 content: "Version two content"
               })
               |> Ash.run_action()

      assert version2.version_number == 2
    end
  end

  describe "approve_version action" do
    test "sets approved_version_id on the piece", %{sequence: sequence} do
      {:ok, piece} =
        Storybox.Stories.ScenePiece
        |> Ash.Changeset.for_create(:create, %{
          title: "Test Scene",
          position: 1,
          sequence_piece_id: sequence.id
        })
        |> Ash.create()

      {:ok, version} =
        Storybox.Stories.ScenePiece
        |> Ash.ActionInput.for_action(:create_version, %{
          scene_piece_id: piece.id,
          content: "Approved content"
        })
        |> Ash.run_action()

      assert {:ok, updated_piece} =
               piece
               |> Ash.Changeset.for_update(:approve_version, %{version_id: version.id})
               |> Ash.update()

      assert updated_piece.approved_version_id == version.id
    end
  end

  describe "set_weights action on SceneVersion" do
    test "sets weights map on a version with empty weights and persists it", %{sequence: sequence} do
      {:ok, piece} =
        Storybox.Stories.ScenePiece
        |> Ash.Changeset.for_create(:create, %{
          title: "Test Scene",
          position: 1,
          sequence_piece_id: sequence.id
        })
        |> Ash.create()

      {:ok, version} =
        Storybox.Stories.SceneVersion
        |> Ash.Changeset.for_create(:create, %{
          scene_piece_id: piece.id,
          content_uri: "storybox://test/scene/v1",
          version_number: 1,
          weights: %{}
        })
        |> Ash.create()

      assert {:ok, updated} =
               version
               |> Ash.Changeset.for_update(:set_weights, %{weights: %{"preference" => 0.6}})
               |> Ash.update()

      assert updated.weights == %{"preference" => 0.6}

      reloaded =
        Storybox.Stories.SceneVersion
        |> Ash.Query.filter(id == ^version.id)
        |> Ash.read_one!(authorize?: false)

      assert reloaded.weights == %{"preference" => 0.6}
    end

    test "replacing weights removes keys not in the new map", %{sequence: sequence} do
      {:ok, piece} =
        Storybox.Stories.ScenePiece
        |> Ash.Changeset.for_create(:create, %{
          title: "Test Scene 2",
          position: 2,
          sequence_piece_id: sequence.id
        })
        |> Ash.create()

      {:ok, version} =
        Storybox.Stories.SceneVersion
        |> Ash.Changeset.for_create(:create, %{
          scene_piece_id: piece.id,
          content_uri: "storybox://test/scene/v2",
          version_number: 1,
          weights: %{"preference" => 0.9, "theme" => 0.7}
        })
        |> Ash.create()

      assert {:ok, updated} =
               version
               |> Ash.Changeset.for_update(:set_weights, %{weights: %{"preference" => 0.4}})
               |> Ash.update()

      assert updated.weights == %{"preference" => 0.4}
      refute Map.has_key?(updated.weights, "theme")
    end
  end

  describe "read" do
    test "returns all scene_pieces", %{sequence: sequence} do
      {:ok, piece1} =
        Storybox.Stories.ScenePiece
        |> Ash.Changeset.for_create(:create, %{
          title: "Scene 1",
          position: 1,
          sequence_piece_id: sequence.id
        })
        |> Ash.create()

      {:ok, piece2} =
        Storybox.Stories.ScenePiece
        |> Ash.Changeset.for_create(:create, %{
          title: "Scene 2",
          position: 2,
          sequence_piece_id: sequence.id
        })
        |> Ash.create()

      assert {:ok, pieces} = Storybox.Stories.ScenePiece |> Ash.read()
      ids = Enum.map(pieces, & &1.id)
      assert piece1.id in ids
      assert piece2.id in ids
    end
  end
end
