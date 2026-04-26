defmodule Storybox.Stories.ScriptViewTest do
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

    {:ok, treatment_view} =
      Storybox.Stories.TreatmentView
      |> Ash.Changeset.for_create(:create, %{
        title: "Act 1",
        position: 1,
        story_id: story.id
      })
      |> Ash.create()

    {:ok, scene} =
      Storybox.Stories.Scene
      |> Ash.Changeset.for_create(:create, %{title: "Opening Scene", story_id: story.id})
      |> Ash.create()

    {:ok, _tvs} =
      Storybox.Stories.TreatmentViewScene
      |> Ash.Changeset.for_create(:create, %{
        treatment_view_id: treatment_view.id,
        scene_id: scene.id,
        position: 1
      })
      |> Ash.create()

    %{story: story, scene: scene}
  end

  describe "create script_view" do
    test "creates a script_view with required fields", %{scene: scene} do
      assert {:ok, view} =
               Storybox.Stories.ScriptView
               |> Ash.Changeset.for_create(:create, %{
                 title: "Opening Scene",
                 scene_id: scene.id
               })
               |> Ash.create()

      assert view.title == "Opening Scene"
      assert view.scene_id == scene.id
      assert is_nil(view.approved_version_id)
    end

    test "fails without title", %{scene: scene} do
      assert {:error, %Ash.Error.Invalid{}} =
               Storybox.Stories.ScriptView
               |> Ash.Changeset.for_create(:create, %{scene_id: scene.id})
               |> Ash.create()
    end

    test "fails without scene_id" do
      assert {:error, %Ash.Error.Invalid{}} =
               Storybox.Stories.ScriptView
               |> Ash.Changeset.for_create(:create, %{title: "Test"})
               |> Ash.create()
    end
  end

  describe "create_version action" do
    test "creates first version with version_number 1", %{story: story, scene: scene} do
      {:ok, view} =
        Storybox.Stories.ScriptView
        |> Ash.Changeset.for_create(:create, %{title: "Opening Scene", scene_id: scene.id})
        |> Ash.create()

      assert {:ok, piece} =
               Storybox.Stories.ScriptView
               |> Ash.ActionInput.for_action(:create_version, %{
                 script_view_id: view.id,
                 content: "INT. COFFEE SHOP - DAY"
               })
               |> Ash.run_action()

      assert piece.version_number == 1
      assert piece.upstream_status == :current
      assert piece.weights == %{}
      assert piece.script_view_id == view.id

      assert piece.content_uri ==
               Storybox.Storage.uri_for_scene(story.id, view.id, 1)
    end

    test "increments version_number for subsequent versions", %{scene: scene} do
      {:ok, view} =
        Storybox.Stories.ScriptView
        |> Ash.Changeset.for_create(:create, %{title: "Test Scene", scene_id: scene.id})
        |> Ash.create()

      {:ok, _piece1} =
        Storybox.Stories.ScriptView
        |> Ash.ActionInput.for_action(:create_version, %{
          script_view_id: view.id,
          content: "Version one content"
        })
        |> Ash.run_action()

      assert {:ok, piece2} =
               Storybox.Stories.ScriptView
               |> Ash.ActionInput.for_action(:create_version, %{
                 script_view_id: view.id,
                 content: "Version two content"
               })
               |> Ash.run_action()

      assert piece2.version_number == 2
    end
  end

  describe "approve_version action" do
    test "sets approved_version_id on the view", %{scene: scene} do
      {:ok, view} =
        Storybox.Stories.ScriptView
        |> Ash.Changeset.for_create(:create, %{title: "Test Scene", scene_id: scene.id})
        |> Ash.create()

      {:ok, piece} =
        Storybox.Stories.ScriptView
        |> Ash.ActionInput.for_action(:create_version, %{
          script_view_id: view.id,
          content: "Approved content"
        })
        |> Ash.run_action()

      assert {:ok, updated_view} =
               view
               |> Ash.Changeset.for_update(:approve_version, %{version_id: piece.id})
               |> Ash.update()

      assert updated_view.approved_version_id == piece.id
    end
  end

  describe "set_weights action on ScriptPiece" do
    test "sets weights map on a piece with empty weights and persists it", %{scene: scene} do
      {:ok, view} =
        Storybox.Stories.ScriptView
        |> Ash.Changeset.for_create(:create, %{title: "Test Scene", scene_id: scene.id})
        |> Ash.create()

      {:ok, piece} =
        Storybox.Stories.ScriptPiece
        |> Ash.Changeset.for_create(:create, %{
          script_view_id: view.id,
          content_uri: "storybox://test/scene/v1",
          version_number: 1,
          weights: %{}
        })
        |> Ash.create()

      assert {:ok, updated} =
               piece
               |> Ash.Changeset.for_update(:set_weights, %{weights: %{"preference" => 0.6}})
               |> Ash.update()

      assert updated.weights == %{"preference" => 0.6}

      reloaded =
        Storybox.Stories.ScriptPiece
        |> Ash.Query.filter(id == ^piece.id)
        |> Ash.read_one!(authorize?: false)

      assert reloaded.weights == %{"preference" => 0.6}
    end

    test "replacing weights removes keys not in the new map", %{scene: scene} do
      {:ok, view} =
        Storybox.Stories.ScriptView
        |> Ash.Changeset.for_create(:create, %{title: "Test Scene 2", scene_id: scene.id})
        |> Ash.create()

      {:ok, piece} =
        Storybox.Stories.ScriptPiece
        |> Ash.Changeset.for_create(:create, %{
          script_view_id: view.id,
          content_uri: "storybox://test/scene/v2",
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

  describe "read" do
    test "returns all script_views", %{scene: scene} do
      {:ok, view1} =
        Storybox.Stories.ScriptView
        |> Ash.Changeset.for_create(:create, %{title: "Scene 1", scene_id: scene.id})
        |> Ash.create()

      {:ok, view2} =
        Storybox.Stories.ScriptView
        |> Ash.Changeset.for_create(:create, %{title: "Scene 2", scene_id: scene.id})
        |> Ash.create()

      assert {:ok, views} = Storybox.Stories.ScriptView |> Ash.read()
      ids = Enum.map(views, & &1.id)
      assert view1.id in ids
      assert view2.id in ids
    end
  end
end
