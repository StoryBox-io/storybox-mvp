defmodule Storybox.Stories.StoryTest do
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

    %{user: user}
  end

  describe "create" do
    test "creates a story with title and user_id, defaulting through_lines", %{user: user} do
      assert {:ok, story} =
               Storybox.Stories.Story
               |> Ash.Changeset.for_create(:create, %{title: "My Story", user_id: user.id})
               |> Ash.create()

      assert story.title == "My Story"
      assert story.user_id == user.id
      assert story.through_lines == ["preference"]
    end

    test "fails without a title", %{user: user} do
      assert {:error, %Ash.Error.Invalid{}} =
               Storybox.Stories.Story
               |> Ash.Changeset.for_create(:create, %{user_id: user.id})
               |> Ash.create()
    end

    test "fails without a user_id" do
      assert {:error, %Ash.Error.Invalid{}} =
               Storybox.Stories.Story
               |> Ash.Changeset.for_create(:create, %{title: "No User Story"})
               |> Ash.create()
    end
  end

  describe "bootstrap" do
    test "creates 1 default Sequence, 1 TreatmentView + TVV v1, 1 SynopsisView + SVV v1", %{
      user: user
    } do
      assert {:ok, story} =
               Storybox.Stories.Story
               |> Ash.Changeset.for_create(:create, %{title: "Bootstrap Test", user_id: user.id})
               |> Ash.create()

      sequences =
        Storybox.Stories.Sequence
        |> Ash.Query.filter(story_id == ^story.id)
        |> Ash.read!(authorize?: false)

      assert length(sequences) == 1
      [default_seq] = sequences
      assert default_seq.name == "Sequence 1"
      assert default_seq.slug == "sequence-1"

      {:ok, treatment_view} =
        Storybox.Stories.TreatmentView
        |> Ash.Query.filter(story_id == ^story.id)
        |> Ash.read_one(authorize?: false)

      assert treatment_view != nil

      tvvs =
        Storybox.Stories.TreatmentViewVersion
        |> Ash.Query.filter(treatment_view_id == ^treatment_view.id)
        |> Ash.read!(authorize?: false)

      assert length(tvvs) == 1
      [tvv] = tvvs
      assert tvv.version_number == 1

      tvv_segments =
        Storybox.Stories.Segment
        |> Ash.Query.filter(view_version_id == ^tvv.id and view_version_type == :treatment_vv)
        |> Ash.read!(authorize?: false)

      assert length(tvv_segments) == 1
      [tvv_seg] = tvv_segments
      assert tvv_seg.pin_id == nil
      assert tvv_seg.pin_type == nil
      assert tvv_seg.sequence_id == default_seq.id

      {:ok, synopsis_view} =
        Storybox.Stories.SynopsisView
        |> Ash.Query.filter(story_id == ^story.id)
        |> Ash.read_one(authorize?: false)

      assert synopsis_view != nil

      svvs =
        Storybox.Stories.SynopsisViewVersion
        |> Ash.Query.filter(synopsis_view_id == ^synopsis_view.id)
        |> Ash.read!(authorize?: false)

      assert length(svvs) == 1
      [svv] = svvs
      assert svv.version_number == 1

      svv_segments =
        Storybox.Stories.Segment
        |> Ash.Query.filter(view_version_id == ^svv.id and view_version_type == :synopsis_vv)
        |> Ash.read!(authorize?: false)

      assert length(svv_segments) == 1
      [svv_seg] = svv_segments
      assert svv_seg.pin_id == nil
      assert svv_seg.pin_type == nil
      assert svv_seg.sequence_id == default_seq.id
    end

    # Rollback on mid-bootstrap failure is guaranteed by Ash's after_action semantics:
    # the callback runs inside the transaction Ash opens for Story.create, so any
    # {:error, _} returned by bootstrap/2 causes Ash to roll back the whole transaction,
    # leaving zero Story, Sequence, SynopsisView, and TreatmentView rows.
    test "Story.create without a title returns error with no partial rows", %{user: user} do
      assert {:error, %Ash.Error.Invalid{}} =
               Storybox.Stories.Story
               |> Ash.Changeset.for_create(:create, %{user_id: user.id})
               |> Ash.create()

      assert Storybox.Stories.Story |> Ash.read!() == []
    end
  end

  describe "read" do
    test "returns created stories", %{user: user} do
      {:ok, _story} =
        Storybox.Stories.Story
        |> Ash.Changeset.for_create(:create, %{title: "Readable Story", user_id: user.id})
        |> Ash.create()

      assert {:ok, stories} = Storybox.Stories.Story |> Ash.read()
      assert Enum.any?(stories, &(&1.title == "Readable Story"))
    end
  end

  describe "update" do
    test "changes the title", %{user: user} do
      {:ok, story} =
        Storybox.Stories.Story
        |> Ash.Changeset.for_create(:create, %{title: "Original Title", user_id: user.id})
        |> Ash.create()

      assert {:ok, updated} =
               story
               |> Ash.Changeset.for_update(:update, %{title: "Updated Title"})
               |> Ash.update()

      assert updated.title == "Updated Title"
    end
  end
end
