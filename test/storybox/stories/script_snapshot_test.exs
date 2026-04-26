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

    {:ok, treatment_view} =
      Storybox.Stories.TreatmentView
      |> Ash.Changeset.for_create(:create, %{
        title: "Act 1",
        position: 1,
        story_id: story.id
      })
      |> Ash.create()

    %{story: story, treatment_view: treatment_view}
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

  describe "capture action" do
    test "captures approved versions for all script views in a story", %{
      story: story,
      treatment_view: treatment_view
    } do
      {:ok, view1} =
        Storybox.Stories.ScriptView
        |> Ash.Changeset.for_create(:create, %{
          title: "Scene 1",
          position: 1,
          treatment_view_id: treatment_view.id
        })
        |> Ash.create()

      {:ok, view2} =
        Storybox.Stories.ScriptView
        |> Ash.Changeset.for_create(:create, %{
          title: "Scene 2",
          position: 2,
          treatment_view_id: treatment_view.id
        })
        |> Ash.create()

      {:ok, version1} =
        Storybox.Stories.ScriptView
        |> Ash.ActionInput.for_action(:create_version, %{
          script_view_id: view1.id,
          content: "Scene one content"
        })
        |> Ash.run_action()

      {:ok, version2} =
        Storybox.Stories.ScriptView
        |> Ash.ActionInput.for_action(:create_version, %{
          script_view_id: view2.id,
          content: "Scene two content"
        })
        |> Ash.run_action()

      {:ok, view1} =
        view1
        |> Ash.Changeset.for_update(:approve_version, %{version_id: version1.id})
        |> Ash.update()

      {:ok, view2} =
        view2
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

      assert snapshot.entries[to_string(view1.id)] == to_string(view1.approved_version_id)
      assert snapshot.entries[to_string(view2.id)] == to_string(view2.approved_version_id)
    end

    test "excludes script views with no approved version", %{
      story: story,
      treatment_view: treatment_view
    } do
      {:ok, view_approved} =
        Storybox.Stories.ScriptView
        |> Ash.Changeset.for_create(:create, %{
          title: "Approved Scene",
          position: 1,
          treatment_view_id: treatment_view.id
        })
        |> Ash.create()

      {:ok, _view_unapproved} =
        Storybox.Stories.ScriptView
        |> Ash.Changeset.for_create(:create, %{
          title: "Unapproved Scene",
          position: 2,
          treatment_view_id: treatment_view.id
        })
        |> Ash.create()

      {:ok, version} =
        Storybox.Stories.ScriptView
        |> Ash.ActionInput.for_action(:create_version, %{
          script_view_id: view_approved.id,
          content: "Approved scene content"
        })
        |> Ash.run_action()

      {:ok, view_approved} =
        view_approved
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

      assert snapshot.entries[to_string(view_approved.id)] ==
               to_string(view_approved.approved_version_id)
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
