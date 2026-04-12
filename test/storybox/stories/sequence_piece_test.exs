defmodule Storybox.Stories.SequencePieceTest do
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

    %{story: story, user: user}
  end

  describe "create sequence_piece" do
    test "creates a sequence_piece with required fields", %{story: story} do
      assert {:ok, piece} =
               Storybox.Stories.SequencePiece
               |> Ash.Changeset.for_create(:create, %{
                 title: "Act 1 Intro",
                 position: 1,
                 story_id: story.id
               })
               |> Ash.create()

      assert piece.title == "Act 1 Intro"
      assert piece.position == 1
      assert piece.story_id == story.id
      assert is_nil(piece.approved_version_id)
    end

    test "creates a sequence_piece with optional act", %{story: story} do
      assert {:ok, piece} =
               Storybox.Stories.SequencePiece
               |> Ash.Changeset.for_create(:create, %{
                 title: "Intro",
                 position: 1,
                 story_id: story.id,
                 act: "Act 1"
               })
               |> Ash.create()

      assert piece.act == "Act 1"
    end

    test "fails without title", %{story: story} do
      assert {:error, %Ash.Error.Invalid{}} =
               Storybox.Stories.SequencePiece
               |> Ash.Changeset.for_create(:create, %{
                 position: 1,
                 story_id: story.id
               })
               |> Ash.create()
    end

    test "fails without story_id" do
      assert {:error, %Ash.Error.Invalid{}} =
               Storybox.Stories.SequencePiece
               |> Ash.Changeset.for_create(:create, %{
                 title: "Test",
                 position: 1
               })
               |> Ash.create()
    end
  end

  describe "create_version action" do
    test "creates first version with version_number 1", %{story: story} do
      {:ok, piece} =
        Storybox.Stories.SequencePiece
        |> Ash.Changeset.for_create(:create, %{
          title: "First Act",
          position: 1,
          story_id: story.id
        })
        |> Ash.create()

      assert {:ok, version} =
               Storybox.Stories.SequencePiece
               |> Ash.ActionInput.for_action(:create_version, %{
                 sequence_piece_id: piece.id,
                 content: "INT. COFFEE SHOP - DAY"
               })
               |> Ash.run_action()

      assert version.version_number == 1
      assert version.upstream_status == :current
      assert version.weights == %{}
      assert version.sequence_piece_id == piece.id

      assert version.content_uri ==
               Storybox.Storage.uri_for_sequence(story.id, piece.id, 1)
    end

    test "increments version_number for subsequent versions", %{story: story} do
      {:ok, piece} =
        Storybox.Stories.SequencePiece
        |> Ash.Changeset.for_create(:create, %{
          title: "Test Piece",
          position: 1,
          story_id: story.id
        })
        |> Ash.create()

      {:ok, _version1} =
        Storybox.Stories.SequencePiece
        |> Ash.ActionInput.for_action(:create_version, %{
          sequence_piece_id: piece.id,
          content: "Version one content"
        })
        |> Ash.run_action()

      assert {:ok, version2} =
               Storybox.Stories.SequencePiece
               |> Ash.ActionInput.for_action(:create_version, %{
                 sequence_piece_id: piece.id,
                 content: "Version two content"
               })
               |> Ash.run_action()

      assert version2.version_number == 2
    end
  end

  describe "approve_version action" do
    test "sets approved_version_id on the piece", %{story: story} do
      {:ok, piece} =
        Storybox.Stories.SequencePiece
        |> Ash.Changeset.for_create(:create, %{
          title: "Test Piece",
          position: 1,
          story_id: story.id
        })
        |> Ash.create()

      {:ok, version} =
        Storybox.Stories.SequencePiece
        |> Ash.ActionInput.for_action(:create_version, %{
          sequence_piece_id: piece.id,
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

  describe "set_weights action on SequenceVersion" do
    test "sets weights map on a version with empty weights and persists it", %{story: story} do
      {:ok, piece} =
        Storybox.Stories.SequencePiece
        |> Ash.Changeset.for_create(:create, %{
          title: "Test Piece",
          position: 1,
          story_id: story.id
        })
        |> Ash.create()

      {:ok, version} =
        Storybox.Stories.SequenceVersion
        |> Ash.Changeset.for_create(:create, %{
          sequence_piece_id: piece.id,
          content_uri: "storybox://test/v1",
          version_number: 1,
          weights: %{}
        })
        |> Ash.create()

      assert {:ok, updated} =
               version
               |> Ash.Changeset.for_update(:set_weights, %{weights: %{"preference" => 0.8}})
               |> Ash.update()

      assert updated.weights == %{"preference" => 0.8}

      reloaded =
        Storybox.Stories.SequenceVersion
        |> Ash.Query.filter(id == ^version.id)
        |> Ash.read_one!(authorize?: false)

      assert reloaded.weights == %{"preference" => 0.8}
    end

    test "replacing weights removes keys not in the new map", %{story: story} do
      {:ok, piece} =
        Storybox.Stories.SequencePiece
        |> Ash.Changeset.for_create(:create, %{
          title: "Test Piece",
          position: 2,
          story_id: story.id
        })
        |> Ash.create()

      {:ok, version} =
        Storybox.Stories.SequenceVersion
        |> Ash.Changeset.for_create(:create, %{
          sequence_piece_id: piece.id,
          content_uri: "storybox://test/v2",
          version_number: 1,
          weights: %{"preference" => 0.9, "theme" => 0.7}
        })
        |> Ash.create()

      assert {:ok, updated} =
               version
               |> Ash.Changeset.for_update(:set_weights, %{weights: %{"preference" => 0.5}})
               |> Ash.update()

      assert updated.weights == %{"preference" => 0.5}
      refute Map.has_key?(updated.weights, "theme")
    end
  end

  describe "read" do
    test "returns all sequence_pieces", %{story: story} do
      {:ok, piece1} =
        Storybox.Stories.SequencePiece
        |> Ash.Changeset.for_create(:create, %{
          title: "Piece 1",
          position: 1,
          story_id: story.id
        })
        |> Ash.create()

      {:ok, piece2} =
        Storybox.Stories.SequencePiece
        |> Ash.Changeset.for_create(:create, %{
          title: "Piece 2",
          position: 2,
          story_id: story.id
        })
        |> Ash.create()

      assert {:ok, pieces} = Storybox.Stories.SequencePiece |> Ash.read()
      ids = Enum.map(pieces, & &1.id)
      assert piece1.id in ids
      assert piece2.id in ids
    end
  end
end
