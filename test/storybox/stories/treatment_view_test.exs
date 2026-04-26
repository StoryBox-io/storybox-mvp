defmodule Storybox.Stories.TreatmentViewTest do
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

  describe "create treatment_view" do
    test "creates a treatment_view with required fields", %{story: story} do
      assert {:ok, view} =
               Storybox.Stories.TreatmentView
               |> Ash.Changeset.for_create(:create, %{
                 title: "Act 1 Intro",
                 position: 1,
                 story_id: story.id
               })
               |> Ash.create()

      assert view.title == "Act 1 Intro"
      assert view.position == 1
      assert view.story_id == story.id
      assert is_nil(view.approved_version_id)
    end

    test "creates a treatment_view with optional act", %{story: story} do
      assert {:ok, view} =
               Storybox.Stories.TreatmentView
               |> Ash.Changeset.for_create(:create, %{
                 title: "Intro",
                 position: 1,
                 story_id: story.id,
                 act: "Act 1"
               })
               |> Ash.create()

      assert view.act == "Act 1"
    end

    test "fails without title", %{story: story} do
      assert {:error, %Ash.Error.Invalid{}} =
               Storybox.Stories.TreatmentView
               |> Ash.Changeset.for_create(:create, %{
                 position: 1,
                 story_id: story.id
               })
               |> Ash.create()
    end

    test "fails without story_id" do
      assert {:error, %Ash.Error.Invalid{}} =
               Storybox.Stories.TreatmentView
               |> Ash.Changeset.for_create(:create, %{
                 title: "Test",
                 position: 1
               })
               |> Ash.create()
    end
  end

  describe "create_version action" do
    test "creates first version with version_number 1", %{story: story} do
      {:ok, view} =
        Storybox.Stories.TreatmentView
        |> Ash.Changeset.for_create(:create, %{
          title: "First Act",
          position: 1,
          story_id: story.id
        })
        |> Ash.create()

      assert {:ok, piece} =
               Storybox.Stories.TreatmentView
               |> Ash.ActionInput.for_action(:create_version, %{
                 treatment_view_id: view.id,
                 content: "INT. COFFEE SHOP - DAY"
               })
               |> Ash.run_action()

      assert piece.version_number == 1
      assert piece.upstream_status == :current
      assert piece.weights == %{}
      assert piece.treatment_view_id == view.id

      assert piece.content_uri ==
               Storybox.Storage.uri_for_sequence(story.id, view.id, 1)
    end

    test "increments version_number for subsequent versions", %{story: story} do
      {:ok, view} =
        Storybox.Stories.TreatmentView
        |> Ash.Changeset.for_create(:create, %{
          title: "Test View",
          position: 1,
          story_id: story.id
        })
        |> Ash.create()

      {:ok, _piece1} =
        Storybox.Stories.TreatmentView
        |> Ash.ActionInput.for_action(:create_version, %{
          treatment_view_id: view.id,
          content: "Version one content"
        })
        |> Ash.run_action()

      assert {:ok, piece2} =
               Storybox.Stories.TreatmentView
               |> Ash.ActionInput.for_action(:create_version, %{
                 treatment_view_id: view.id,
                 content: "Version two content"
               })
               |> Ash.run_action()

      assert piece2.version_number == 2
    end
  end

  describe "approve_version action" do
    test "sets approved_version_id on the view", %{story: story} do
      {:ok, view} =
        Storybox.Stories.TreatmentView
        |> Ash.Changeset.for_create(:create, %{
          title: "Test View",
          position: 1,
          story_id: story.id
        })
        |> Ash.create()

      {:ok, piece} =
        Storybox.Stories.TreatmentView
        |> Ash.ActionInput.for_action(:create_version, %{
          treatment_view_id: view.id,
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

  describe "set_weights action on TreatmentPiece" do
    test "sets weights map on a piece with empty weights and persists it", %{story: story} do
      {:ok, view} =
        Storybox.Stories.TreatmentView
        |> Ash.Changeset.for_create(:create, %{
          title: "Test View",
          position: 1,
          story_id: story.id
        })
        |> Ash.create()

      {:ok, piece} =
        Storybox.Stories.TreatmentPiece
        |> Ash.Changeset.for_create(:create, %{
          treatment_view_id: view.id,
          content_uri: "storybox://test/v1",
          version_number: 1,
          weights: %{}
        })
        |> Ash.create()

      assert {:ok, updated} =
               piece
               |> Ash.Changeset.for_update(:set_weights, %{weights: %{"preference" => 0.8}})
               |> Ash.update()

      assert updated.weights == %{"preference" => 0.8}

      reloaded =
        Storybox.Stories.TreatmentPiece
        |> Ash.Query.filter(id == ^piece.id)
        |> Ash.read_one!(authorize?: false)

      assert reloaded.weights == %{"preference" => 0.8}
    end

    test "replacing weights removes keys not in the new map", %{story: story} do
      {:ok, view} =
        Storybox.Stories.TreatmentView
        |> Ash.Changeset.for_create(:create, %{
          title: "Test View",
          position: 2,
          story_id: story.id
        })
        |> Ash.create()

      {:ok, piece} =
        Storybox.Stories.TreatmentPiece
        |> Ash.Changeset.for_create(:create, %{
          treatment_view_id: view.id,
          content_uri: "storybox://test/v2",
          version_number: 1,
          weights: %{"preference" => 0.9, "theme" => 0.7}
        })
        |> Ash.create()

      assert {:ok, updated} =
               piece
               |> Ash.Changeset.for_update(:set_weights, %{weights: %{"preference" => 0.5}})
               |> Ash.update()

      assert updated.weights == %{"preference" => 0.5}
      refute Map.has_key?(updated.weights, "theme")
    end
  end

  describe "read" do
    test "returns all treatment_views", %{story: story} do
      {:ok, view1} =
        Storybox.Stories.TreatmentView
        |> Ash.Changeset.for_create(:create, %{
          title: "View 1",
          position: 1,
          story_id: story.id
        })
        |> Ash.create()

      {:ok, view2} =
        Storybox.Stories.TreatmentView
        |> Ash.Changeset.for_create(:create, %{
          title: "View 2",
          position: 2,
          story_id: story.id
        })
        |> Ash.create()

      assert {:ok, views} = Storybox.Stories.TreatmentView |> Ash.read()
      ids = Enum.map(views, & &1.id)
      assert view1.id in ids
      assert view2.id in ids
    end
  end
end
