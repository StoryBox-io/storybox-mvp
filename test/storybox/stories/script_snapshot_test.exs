defmodule Storybox.Stories.ScriptSnapshotTest do
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

    %{story: story, sequence: sequence}
  end

  describe "create" do
    test "creates a snapshot with explicit entries", %{story: story} do
      entries = %{"scene-piece-1" => "scene-version-1"}

      assert {:ok, snapshot} =
               Storybox.Stories.ScriptSnapshot
               |> Ash.Changeset.for_create(:create, %{
                 name: "Draft 1",
                 entries: entries,
                 story_id: story.id
               })
               |> Ash.create()

      assert snapshot.name == "Draft 1"
      assert snapshot.entries == entries
      assert snapshot.story_id == story.id
    end

    test "creates a snapshot with empty entries by default", %{story: story} do
      assert {:ok, snapshot} =
               Storybox.Stories.ScriptSnapshot
               |> Ash.Changeset.for_create(:create, %{
                 name: "Empty Snapshot",
                 story_id: story.id
               })
               |> Ash.create()

      assert snapshot.entries == %{}
    end

    test "fails without name", %{story: story} do
      assert {:error, %Ash.Error.Invalid{}} =
               Storybox.Stories.ScriptSnapshot
               |> Ash.Changeset.for_create(:create, %{story_id: story.id})
               |> Ash.create()
    end

    test "fails without story_id" do
      assert {:error, %Ash.Error.Invalid{}} =
               Storybox.Stories.ScriptSnapshot
               |> Ash.Changeset.for_create(:create, %{name: "Snapshot"})
               |> Ash.create()
    end
  end

  describe "read" do
    test "returns snapshots for a story", %{story: story} do
      {:ok, snap1} =
        Storybox.Stories.ScriptSnapshot
        |> Ash.Changeset.for_create(:create, %{name: "Snap 1", story_id: story.id})
        |> Ash.create()

      {:ok, snap2} =
        Storybox.Stories.ScriptSnapshot
        |> Ash.Changeset.for_create(:create, %{name: "Snap 2", story_id: story.id})
        |> Ash.create()

      assert {:ok, snapshots} = Storybox.Stories.ScriptSnapshot |> Ash.read()
      ids = Enum.map(snapshots, & &1.id)
      assert snap1.id in ids
      assert snap2.id in ids
    end
  end

  describe "capture action" do
    test "captures approved versions for all scene pieces in a story", %{
      story: story,
      sequence: sequence
    } do
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

      {:ok, version1} =
        Storybox.Stories.ScenePiece
        |> Ash.ActionInput.for_action(:create_version, %{
          scene_piece_id: piece1.id,
          content: "Scene one content"
        })
        |> Ash.run_action()

      {:ok, version2} =
        Storybox.Stories.ScenePiece
        |> Ash.ActionInput.for_action(:create_version, %{
          scene_piece_id: piece2.id,
          content: "Scene two content"
        })
        |> Ash.run_action()

      {:ok, piece1} =
        piece1
        |> Ash.Changeset.for_update(:approve_version, %{version_id: version1.id})
        |> Ash.update()

      {:ok, piece2} =
        piece2
        |> Ash.Changeset.for_update(:approve_version, %{version_id: version2.id})
        |> Ash.update()

      assert {:ok, snapshot} =
               Storybox.Stories.ScriptSnapshot
               |> Ash.ActionInput.for_action(:capture, %{
                 story_id: story.id,
                 name: "Before Workshop"
               })
               |> Ash.run_action()

      assert snapshot.name == "Before Workshop"
      assert snapshot.story_id == story.id

      assert snapshot.entries[to_string(piece1.id)] == to_string(piece1.approved_version_id)
      assert snapshot.entries[to_string(piece2.id)] == to_string(piece2.approved_version_id)
    end

    test "excludes scene pieces with no approved version", %{story: story, sequence: sequence} do
      {:ok, piece_approved} =
        Storybox.Stories.ScenePiece
        |> Ash.Changeset.for_create(:create, %{
          title: "Approved Scene",
          position: 1,
          sequence_piece_id: sequence.id
        })
        |> Ash.create()

      {:ok, _piece_unapproved} =
        Storybox.Stories.ScenePiece
        |> Ash.Changeset.for_create(:create, %{
          title: "Unapproved Scene",
          position: 2,
          sequence_piece_id: sequence.id
        })
        |> Ash.create()

      {:ok, version} =
        Storybox.Stories.ScenePiece
        |> Ash.ActionInput.for_action(:create_version, %{
          scene_piece_id: piece_approved.id,
          content: "Approved scene content"
        })
        |> Ash.run_action()

      {:ok, piece_approved} =
        piece_approved
        |> Ash.Changeset.for_update(:approve_version, %{version_id: version.id})
        |> Ash.update()

      assert {:ok, snapshot} =
               Storybox.Stories.ScriptSnapshot
               |> Ash.ActionInput.for_action(:capture, %{
                 story_id: story.id,
                 name: "Partial Snapshot"
               })
               |> Ash.run_action()

      assert map_size(snapshot.entries) == 1

      assert snapshot.entries[to_string(piece_approved.id)] ==
               to_string(piece_approved.approved_version_id)
    end

    test "capture with no scene pieces produces empty entries", %{story: story} do
      assert {:ok, snapshot} =
               Storybox.Stories.ScriptSnapshot
               |> Ash.ActionInput.for_action(:capture, %{
                 story_id: story.id,
                 name: "Empty Story Snapshot"
               })
               |> Ash.run_action()

      assert snapshot.entries == %{}
    end
  end
end
