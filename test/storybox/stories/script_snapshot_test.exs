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

    make_scene = fn title ->
      {:ok, scene} =
        Storybox.Stories.Scene
        |> Ash.Changeset.for_create(:create, %{title: title, story_id: story.id})
        |> Ash.create()

      scene
    end

    %{story: story, make_scene: make_scene}
  end

  describe "create" do
    test "creates a snapshot with explicit entries", %{story: story} do
      entries = %{"script-view-1" => "script-piece-1"}

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

  # capture action: approved_version_id was removed from ScriptView in issue #94.
  # Capture now always produces empty entries until the new approval mechanism
  # (via ScriptViewVersion) is implemented.
  describe "capture action" do
    test "capture produces empty entries (approval pending redesign via ScriptViewVersion)", %{
      story: story,
      make_scene: make_scene
    } do
      scene1 = make_scene.("Scene 1")
      _scene2 = make_scene.("Scene 2")

      {:ok, _sv1} =
        Storybox.Stories.ScriptView
        |> Ash.Changeset.for_create(:create, %{scene_id: scene1.id})
        |> Ash.create()

      assert {:ok, snapshot} =
               Storybox.Stories.ScriptSnapshot
               |> Ash.ActionInput.for_action(:capture, %{
                 story_id: story.id,
                 name: "Before Workshop"
               })
               |> Ash.run_action()

      assert snapshot.name == "Before Workshop"
      assert snapshot.story_id == story.id
      assert snapshot.entries == %{}
    end

    test "capture with no script views produces empty entries", %{story: story} do
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
