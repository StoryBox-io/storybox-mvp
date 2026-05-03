defmodule Storybox.Stories.SequenceViewTest do
  use Storybox.DataCase

  require Ash.Query

  setup do
    {:ok, user} =
      Storybox.Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "sv_test@example.com",
        password: "password123!",
        password_confirmation: "password123!"
      })
      |> Ash.create()

    {:ok, story} =
      Storybox.Stories.Story
      |> Ash.Changeset.for_create(:create, %{title: "Test Story", user_id: user.id})
      |> Ash.create()

    sequence =
      Storybox.Stories.Sequence
      |> Ash.Query.filter(story_id == ^story.id)
      |> Ash.read_one!(authorize?: false)

    %{story: story, sequence: sequence}
  end

  describe "ensure_for_sequence" do
    test "creates a SequenceView for the sequence with the correct story_id", %{
      story: story,
      sequence: sequence
    } do
      assert {:ok, view} =
               Storybox.Stories.SequenceView
               |> Ash.ActionInput.for_action(:ensure_for_sequence, %{
                 sequence_id: sequence.id,
                 story_id: story.id
               })
               |> Ash.run_action()

      assert view.sequence_id == sequence.id
      assert view.story_id == story.id
    end

    test "is idempotent — second call returns the same record", %{
      story: story,
      sequence: sequence
    } do
      assert {:ok, view1} =
               Storybox.Stories.SequenceView
               |> Ash.ActionInput.for_action(:ensure_for_sequence, %{
                 sequence_id: sequence.id,
                 story_id: story.id
               })
               |> Ash.run_action()

      assert {:ok, view2} =
               Storybox.Stories.SequenceView
               |> Ash.ActionInput.for_action(:ensure_for_sequence, %{
                 sequence_id: sequence.id,
                 story_id: story.id
               })
               |> Ash.run_action()

      assert view1.id == view2.id
    end

    test "DB unique index rejects a second SequenceView with the same (story_id, sequence_id) via direct :create",
         %{story: story, sequence: sequence} do
      {:ok, _view} =
        Storybox.Stories.SequenceView
        |> Ash.Changeset.for_create(:create, %{sequence_id: sequence.id, story_id: story.id})
        |> Ash.create()

      assert {:error, %Ash.Error.Invalid{}} =
               Storybox.Stories.SequenceView
               |> Ash.Changeset.for_create(:create, %{
                 sequence_id: sequence.id,
                 story_id: story.id
               })
               |> Ash.create()
    end
  end
end
