defmodule Storybox.Stories.ScriptPieceTest do
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
      |> Ash.Changeset.for_create(:create, %{title: "Little Witch", user_id: user.id})
      |> Ash.create()

    {:ok, scene_01} =
      Storybox.Stories.Scene
      |> Ash.Changeset.for_create(:create, %{title: "INT. COTTAGE - NIGHT", story_id: story.id})
      |> Ash.create()

    {:ok, scene_02} =
      Storybox.Stories.Scene
      |> Ash.Changeset.for_create(:create, %{title: "EXT. COTTAGE - NIGHT", story_id: story.id})
      |> Ash.create()

    {:ok, sequence} =
      Storybox.Stories.Sequence
      |> Ash.Changeset.for_create(:create, %{
        name: "Act One",
        slug: "act-one",
        story_id: story.id
      })
      |> Ash.create()

    {:ok, sequence_piece} =
      Storybox.Stories.SequencePiece
      |> Ash.Changeset.for_create(:create, %{
        story_id: story.id,
        sequence_id: sequence.id,
        content_uri: Storybox.Storage.uri_for_sequence_piece(story.id, sequence.id, 1),
        version_number: 1
      })
      |> Ash.create()

    %{
      story: story,
      scene_01: scene_01,
      scene_02: scene_02,
      sequence_piece: sequence_piece
    }
  end

  describe "create" do
    test "persists scene_id, content_uri, version_number and defaults", %{scene_01: scene_01} do
      uri = Storybox.Storage.uri_for_script_piece(scene_01.id, 1)

      assert {:ok, piece} =
               Storybox.Stories.ScriptPiece
               |> Ash.Changeset.for_create(:create, %{
                 scene_id: scene_01.id,
                 content_uri: uri,
                 version_number: 1
               })
               |> Ash.create()

      assert piece.scene_id == scene_01.id
      assert piece.content_uri == uri
      assert piece.version_number == 1
      assert piece.weights == %{}
      assert is_nil(piece.source_sequence_piece_id)
      assert is_nil(piece.source_version_at_creation)
    end

    test "persists provenance fields when supplied", %{
      scene_01: scene_01,
      sequence_piece: sp
    } do
      assert {:ok, piece} =
               Storybox.Stories.ScriptPiece
               |> Ash.Changeset.for_create(:create, %{
                 scene_id: scene_01.id,
                 content_uri: Storybox.Storage.uri_for_script_piece(scene_01.id, 1),
                 version_number: 1,
                 source_sequence_piece_id: sp.id,
                 source_version_at_creation: sp.version_number
               })
               |> Ash.create()

      assert piece.source_sequence_piece_id == sp.id
      assert piece.source_version_at_creation == 1
    end

    test "fails without scene_id" do
      assert {:error, %Ash.Error.Invalid{}} =
               Storybox.Stories.ScriptPiece
               |> Ash.Changeset.for_create(:create, %{
                 content_uri: "storybox://scenes/x/script_pieces/v1.fountain",
                 version_number: 1
               })
               |> Ash.create()
    end
  end

  describe "unique_version_per_scene identity" do
    test "rejects a duplicate (scene_id, version_number) via :create", %{scene_01: scene_01} do
      {:ok, _} =
        Storybox.Stories.ScriptPiece
        |> Ash.Changeset.for_create(:create, %{
          scene_id: scene_01.id,
          content_uri: Storybox.Storage.uri_for_script_piece(scene_01.id, 1),
          version_number: 1
        })
        |> Ash.create()

      assert {:error, %Ash.Error.Invalid{}} =
               Storybox.Stories.ScriptPiece
               |> Ash.Changeset.for_create(:create, %{
                 scene_id: scene_01.id,
                 content_uri: Storybox.Storage.uri_for_script_piece(scene_01.id, 1),
                 version_number: 1
               })
               |> Ash.create()
    end
  end

  describe "create_version action" do
    test "scene_01 v1 with provenance — version 1, URI under scene_01, provenance set", %{
      scene_01: scene_01,
      sequence_piece: sp
    } do
      assert {:ok, piece} =
               Storybox.Stories.ScriptPiece
               |> Ash.ActionInput.for_action(:create_version, %{
                 scene_id: scene_01.id,
                 content: "INT. COTTAGE - NIGHT\n\nThe witch stirs.",
                 source_sequence_piece_id: sp.id,
                 source_version_at_creation: sp.version_number
               })
               |> Ash.run_action()

      assert piece.scene_id == scene_01.id
      assert piece.version_number == 1
      assert piece.source_sequence_piece_id == sp.id
      assert piece.source_version_at_creation == 1

      assert piece.content_uri ==
               Storybox.Storage.uri_for_script_piece(scene_01.id, 1)
    end

    test "scene_01 v2 without provenance — version 2, provenance fields nil", %{
      scene_01: scene_01
    } do
      {:ok, _v1} =
        Storybox.Stories.ScriptPiece
        |> Ash.ActionInput.for_action(:create_version, %{
          scene_id: scene_01.id,
          content: "Draft one."
        })
        |> Ash.run_action()

      assert {:ok, v2} =
               Storybox.Stories.ScriptPiece
               |> Ash.ActionInput.for_action(:create_version, %{
                 scene_id: scene_01.id,
                 content: "Draft two."
               })
               |> Ash.run_action()

      assert v2.version_number == 2
      assert is_nil(v2.source_sequence_piece_id)
      assert is_nil(v2.source_version_at_creation)

      assert v2.content_uri ==
               Storybox.Storage.uri_for_script_piece(scene_01.id, 2)
    end

    test "scene_02 counter is independent of scene_01", %{
      scene_01: scene_01,
      scene_02: scene_02
    } do
      {:ok, _} =
        Storybox.Stories.ScriptPiece
        |> Ash.ActionInput.for_action(:create_version, %{
          scene_id: scene_01.id,
          content: "scene_01 v1."
        })
        |> Ash.run_action()

      {:ok, _} =
        Storybox.Stories.ScriptPiece
        |> Ash.ActionInput.for_action(:create_version, %{
          scene_id: scene_01.id,
          content: "scene_01 v2."
        })
        |> Ash.run_action()

      assert {:ok, scene_02_v1} =
               Storybox.Stories.ScriptPiece
               |> Ash.ActionInput.for_action(:create_version, %{
                 scene_id: scene_02.id,
                 content: "scene_02 v1."
               })
               |> Ash.run_action()

      assert scene_02_v1.version_number == 1
      assert scene_02_v1.scene_id == scene_02.id
    end
  end

  describe "Scene.script_pieces association" do
    test "returns ScriptPieces for the Scene only", %{
      scene_01: scene_01,
      scene_02: scene_02
    } do
      {:ok, _} =
        Storybox.Stories.ScriptPiece
        |> Ash.ActionInput.for_action(:create_version, %{
          scene_id: scene_01.id,
          content: "scene_01 a."
        })
        |> Ash.run_action()

      {:ok, _} =
        Storybox.Stories.ScriptPiece
        |> Ash.ActionInput.for_action(:create_version, %{
          scene_id: scene_01.id,
          content: "scene_01 b."
        })
        |> Ash.run_action()

      {:ok, _} =
        Storybox.Stories.ScriptPiece
        |> Ash.ActionInput.for_action(:create_version, %{
          scene_id: scene_02.id,
          content: "scene_02 a."
        })
        |> Ash.run_action()

      {:ok, loaded} = Ash.load(scene_01, :script_pieces)
      assert length(loaded.script_pieces) == 2
      assert Enum.all?(loaded.script_pieces, &(&1.scene_id == scene_01.id))
    end
  end

  describe "Story does not own ScriptPieces" do
    test "Story resource has no :script_pieces relationship" do
      relationships = Ash.Resource.Info.relationships(Storybox.Stories.Story)
      names = Enum.map(relationships, & &1.name)
      refute :script_pieces in names
    end
  end

  describe "ScriptPiece resource shape" do
    test "has no upstream_status attribute" do
      attrs = Ash.Resource.Info.attributes(Storybox.Stories.ScriptPiece)
      names = Enum.map(attrs, & &1.name)
      refute :upstream_status in names
    end

    test "has no :mark_stale action" do
      actions = Ash.Resource.Info.actions(Storybox.Stories.ScriptPiece)
      names = Enum.map(actions, & &1.name)
      refute :mark_stale in names
    end

    test "has no :script_view relationship" do
      relationships = Ash.Resource.Info.relationships(Storybox.Stories.ScriptPiece)
      names = Enum.map(relationships, & &1.name)
      refute :script_view in names
    end
  end

  describe "set_weights action" do
    test "replaces the weights map entirely", %{scene_01: scene_01} do
      {:ok, piece} =
        Storybox.Stories.ScriptPiece
        |> Ash.Changeset.for_create(:create, %{
          scene_id: scene_01.id,
          content_uri: Storybox.Storage.uri_for_script_piece(scene_01.id, 1),
          version_number: 1,
          weights: %{"preference" => 0.9, "theme" => 0.7}
        })
        |> Ash.create()

      assert {:ok, updated} =
               piece
               |> Ash.Changeset.for_update(:set_weights, %{weights: %{"preference" => 0.4}})
               |> Ash.update()

      assert updated.weights == %{"preference" => 0.4}
      refute Map.has_key?(updated.weights, "theme")
    end
  end
end
