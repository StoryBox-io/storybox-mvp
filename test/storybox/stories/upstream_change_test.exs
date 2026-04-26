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

    {:ok, treatment_view} =
      Storybox.Stories.TreatmentView
      |> Ash.Changeset.for_create(:create, %{
        title: "Act 1",
        position: 1,
        story_id: story.id
      })
      |> Ash.create()

    {:ok, treatment_piece} =
      Storybox.Stories.TreatmentPiece
      |> Ash.Changeset.for_create(:create, %{
        treatment_view_id: treatment_view.id,
        content_uri: "storybox://stories/#{story.id}/sequences/#{treatment_view.id}/v1",
        version_number: 1
      })
      |> Ash.create()

    {:ok, script_view} =
      Storybox.Stories.ScriptView
      |> Ash.Changeset.for_create(:create, %{
        title: "Scene 1",
        position: 1,
        treatment_view_id: treatment_view.id
      })
      |> Ash.create()

    {:ok, script_piece} =
      Storybox.Stories.ScriptPiece
      |> Ash.Changeset.for_create(:create, %{
        script_view_id: script_view.id,
        content_uri: "storybox://stories/#{story.id}/scenes/#{script_view.id}/v1",
        version_number: 1
      })
      |> Ash.create()

    %{
      story: story,
      treatment_piece: treatment_piece,
      script_piece: script_piece
    }
  end

  describe "create" do
    test "creates an UpstreamChange for a treatment_piece target", %{
      story: story,
      treatment_piece: treatment_piece
    } do
      assert {:ok, change} =
               Storybox.Stories.UpstreamChange
               |> Ash.Changeset.for_create(:create, %{
                 piece_version_type: :treatment_piece,
                 piece_version_id: treatment_piece.id,
                 component_type: :story,
                 component_id: story.id,
                 version_before: "2026-01-01T00:00:00Z",
                 version_after: "2026-02-01T00:00:00Z"
               })
               |> Ash.create()

      assert change.piece_version_type == :treatment_piece
      assert change.piece_version_id == treatment_piece.id
      assert change.component_type == :story
      assert change.component_id == story.id
      assert change.version_before == "2026-01-01T00:00:00Z"
      assert change.version_after == "2026-02-01T00:00:00Z"
      assert change.acknowledged == false
    end

    test "creates an UpstreamChange for a script_piece target", %{
      story: story,
      script_piece: script_piece
    } do
      assert {:ok, change} =
               Storybox.Stories.UpstreamChange
               |> Ash.Changeset.for_create(:create, %{
                 piece_version_type: :script_piece,
                 piece_version_id: script_piece.id,
                 component_type: :character,
                 component_id: story.id
               })
               |> Ash.create()

      assert change.piece_version_type == :script_piece
      assert change.component_type == :character
      assert change.acknowledged == false
      assert is_nil(change.version_before)
      assert is_nil(change.version_after)
    end

    test "defaults acknowledged to false", %{story: story, script_piece: script_piece} do
      assert {:ok, change} =
               Storybox.Stories.UpstreamChange
               |> Ash.Changeset.for_create(:create, %{
                 piece_version_type: :script_piece,
                 piece_version_id: script_piece.id,
                 component_type: :world,
                 component_id: story.id
               })
               |> Ash.create()

      assert change.acknowledged == false
    end

    test "fails with invalid piece_version_type", %{story: story, script_piece: script_piece} do
      assert {:error, %Ash.Error.Invalid{}} =
               Storybox.Stories.UpstreamChange
               |> Ash.Changeset.for_create(:create, %{
                 piece_version_type: :bad_type,
                 piece_version_id: script_piece.id,
                 component_type: :story,
                 component_id: story.id
               })
               |> Ash.create()
    end

    test "fails with invalid component_type", %{story: story, script_piece: script_piece} do
      assert {:error, %Ash.Error.Invalid{}} =
               Storybox.Stories.UpstreamChange
               |> Ash.Changeset.for_create(:create, %{
                 piece_version_type: :script_piece,
                 piece_version_id: script_piece.id,
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
    test "sets acknowledged to true", %{story: story, script_piece: script_piece} do
      {:ok, change} =
        Storybox.Stories.UpstreamChange
        |> Ash.Changeset.for_create(:create, %{
          piece_version_type: :script_piece,
          piece_version_id: script_piece.id,
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
    test "filters by component_type", %{story: story, script_piece: script_piece} do
      {:ok, _} =
        Storybox.Stories.UpstreamChange
        |> Ash.Changeset.for_create(:create, %{
          piece_version_type: :script_piece,
          piece_version_id: script_piece.id,
          component_type: :story,
          component_id: story.id
        })
        |> Ash.create()

      {:ok, _} =
        Storybox.Stories.UpstreamChange
        |> Ash.Changeset.for_create(:create, %{
          piece_version_type: :script_piece,
          piece_version_id: script_piece.id,
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
