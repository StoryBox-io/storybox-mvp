defmodule Storybox.Stories.TreatmentViewSceneTest do
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
      |> Ash.Changeset.for_create(:create, %{title: "Scene A", story_id: story.id})
      |> Ash.create()

    %{story: story, treatment_view: treatment_view, scene: scene}
  end

  describe "create" do
    test "creates a join record with position", %{treatment_view: tv, scene: scene} do
      assert {:ok, tvs} =
               Storybox.Stories.TreatmentViewScene
               |> Ash.Changeset.for_create(:create, %{
                 treatment_view_id: tv.id,
                 scene_id: scene.id,
                 position: 1
               })
               |> Ash.create()

      assert tvs.treatment_view_id == tv.id
      assert tvs.scene_id == scene.id
      assert tvs.position == 1
    end

    test "fails without treatment_view_id", %{scene: scene} do
      assert {:error, %Ash.Error.Invalid{}} =
               Storybox.Stories.TreatmentViewScene
               |> Ash.Changeset.for_create(:create, %{scene_id: scene.id, position: 1})
               |> Ash.create()
    end

    test "fails without scene_id", %{treatment_view: tv} do
      assert {:error, %Ash.Error.Invalid{}} =
               Storybox.Stories.TreatmentViewScene
               |> Ash.Changeset.for_create(:create, %{treatment_view_id: tv.id, position: 1})
               |> Ash.create()
    end

    test "fails without position", %{treatment_view: tv, scene: scene} do
      assert {:error, %Ash.Error.Invalid{}} =
               Storybox.Stories.TreatmentViewScene
               |> Ash.Changeset.for_create(:create, %{
                 treatment_view_id: tv.id,
                 scene_id: scene.id
               })
               |> Ash.create()
    end
  end

  describe "ordering" do
    test "scenes can be ordered by position", %{story: story, treatment_view: tv} do
      {:ok, scene_b} =
        Storybox.Stories.Scene
        |> Ash.Changeset.for_create(:create, %{title: "Scene B", story_id: story.id})
        |> Ash.create()

      {:ok, scene_a} =
        Storybox.Stories.Scene
        |> Ash.Changeset.for_create(:create, %{title: "Scene A", story_id: story.id})
        |> Ash.create()

      {:ok, _} =
        Storybox.Stories.TreatmentViewScene
        |> Ash.Changeset.for_create(:create, %{
          treatment_view_id: tv.id,
          scene_id: scene_b.id,
          position: 2
        })
        |> Ash.create()

      {:ok, _} =
        Storybox.Stories.TreatmentViewScene
        |> Ash.Changeset.for_create(:create, %{
          treatment_view_id: tv.id,
          scene_id: scene_a.id,
          position: 1
        })
        |> Ash.create()

      tvs_sorted =
        Storybox.Stories.TreatmentViewScene
        |> Ash.Query.filter(treatment_view_id == ^tv.id)
        |> Ash.Query.sort(position: :asc)
        |> Ash.read!(authorize?: false)

      positions = Enum.map(tvs_sorted, & &1.position)
      assert positions == Enum.sort(positions)
    end
  end

  describe "destroy" do
    test "removes a join record", %{treatment_view: tv, scene: scene} do
      {:ok, tvs} =
        Storybox.Stories.TreatmentViewScene
        |> Ash.Changeset.for_create(:create, %{
          treatment_view_id: tv.id,
          scene_id: scene.id,
          position: 1
        })
        |> Ash.create()

      assert :ok = Ash.destroy(tvs, authorize?: false)

      assert nil ==
               Storybox.Stories.TreatmentViewScene
               |> Ash.Query.filter(id == ^tvs.id)
               |> Ash.read_one!(authorize?: false)
    end
  end
end
