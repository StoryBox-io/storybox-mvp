defmodule Storybox.Stories.SequencePieceTest do
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
      |> Ash.Changeset.for_create(:create, %{title: "Little Witch", user_id: user.id})
      |> Ash.create()

    {:ok, seq1} =
      Storybox.Stories.Sequence
      |> Ash.Changeset.for_create(:create, %{
        name: "Act One",
        slug: "act-one",
        story_id: story.id
      })
      |> Ash.create()

    {:ok, seq2} =
      Storybox.Stories.Sequence
      |> Ash.Changeset.for_create(:create, %{
        name: "Act Two",
        slug: "act-two",
        story_id: story.id
      })
      |> Ash.create()

    %{story: story, seq1: seq1, seq2: seq2}
  end

  describe "create" do
    test "creates a sequence piece with all required fields", %{story: story, seq1: seq1} do
      uri = Storybox.Storage.uri_for_sequence_piece(story.id, seq1.id, 1)

      assert {:ok, piece} =
               Storybox.Stories.SequencePiece
               |> Ash.Changeset.for_create(:create, %{
                 story_id: story.id,
                 sequence_id: seq1.id,
                 content_uri: uri,
                 version_number: 1
               })
               |> Ash.create()

      assert piece.story_id == story.id
      assert piece.sequence_id == seq1.id
      assert piece.content_uri == uri
      assert piece.version_number == 1
      assert piece.weights == %{}
    end

    test "fails without story_id", %{seq1: seq1} do
      assert {:error, %Ash.Error.Invalid{}} =
               Storybox.Stories.SequencePiece
               |> Ash.Changeset.for_create(:create, %{
                 sequence_id: seq1.id,
                 content_uri: "storybox://stories/x/sequences/y/v1.fountain",
                 version_number: 1
               })
               |> Ash.create()
    end

    test "fails without sequence_id", %{story: story} do
      assert {:error, %Ash.Error.Invalid{}} =
               Storybox.Stories.SequencePiece
               |> Ash.Changeset.for_create(:create, %{
                 story_id: story.id,
                 content_uri: "storybox://stories/x/sequences/y/v1.fountain",
                 version_number: 1
               })
               |> Ash.create()
    end
  end

  describe "Story.sequence_pieces association" do
    test "returns all sequence pieces for the story", %{story: story, seq1: seq1, seq2: seq2} do
      uri1 = Storybox.Storage.uri_for_sequence_piece(story.id, seq1.id, 1)
      uri2 = Storybox.Storage.uri_for_sequence_piece(story.id, seq2.id, 1)

      {:ok, _} =
        Storybox.Stories.SequencePiece
        |> Ash.Changeset.for_create(:create, %{
          story_id: story.id,
          sequence_id: seq1.id,
          content_uri: uri1,
          version_number: 1
        })
        |> Ash.create()

      {:ok, _} =
        Storybox.Stories.SequencePiece
        |> Ash.Changeset.for_create(:create, %{
          story_id: story.id,
          sequence_id: seq2.id,
          content_uri: uri2,
          version_number: 1
        })
        |> Ash.create()

      {:ok, loaded} = Ash.load(story, :sequence_pieces)
      assert length(loaded.sequence_pieces) == 2
      assert Enum.all?(loaded.sequence_pieces, &(&1.story_id == story.id))
    end
  end

  describe "create_version action" do
    test "creates act-one v1 with version_number 1 and correct URI", %{
      story: story,
      seq1: seq1
    } do
      assert {:ok, piece} =
               Storybox.Stories.SequencePiece
               |> Ash.ActionInput.for_action(:create_version, %{
                 story_id: story.id,
                 sequence_id: seq1.id,
                 content: "Act one treatment."
               })
               |> Ash.run_action()

      assert piece.version_number == 1
      assert piece.sequence_id == seq1.id

      assert piece.content_uri ==
               Storybox.Storage.uri_for_sequence_piece(story.id, seq1.id, 1)
    end

    test "creates act-one v2 — version 2, correct URI", %{
      story: story,
      seq1: seq1
    } do
      {:ok, _} =
        Storybox.Stories.SequencePiece
        |> Ash.ActionInput.for_action(:create_version, %{
          story_id: story.id,
          sequence_id: seq1.id,
          content: "Draft one."
        })
        |> Ash.run_action()

      assert {:ok, v2} =
               Storybox.Stories.SequencePiece
               |> Ash.ActionInput.for_action(:create_version, %{
                 story_id: story.id,
                 sequence_id: seq1.id,
                 content: "Draft two."
               })
               |> Ash.run_action()

      assert v2.version_number == 2

      assert v2.content_uri ==
               Storybox.Storage.uri_for_sequence_piece(story.id, seq1.id, 2)
    end

    test "act-two version counter is independent of act-one", %{
      story: story,
      seq1: seq1,
      seq2: seq2
    } do
      {:ok, _} =
        Storybox.Stories.SequencePiece
        |> Ash.ActionInput.for_action(:create_version, %{
          story_id: story.id,
          sequence_id: seq1.id,
          content: "Act one v1."
        })
        |> Ash.run_action()

      {:ok, _} =
        Storybox.Stories.SequencePiece
        |> Ash.ActionInput.for_action(:create_version, %{
          story_id: story.id,
          sequence_id: seq1.id,
          content: "Act one v2."
        })
        |> Ash.run_action()

      assert {:ok, act_two_v1} =
               Storybox.Stories.SequencePiece
               |> Ash.ActionInput.for_action(:create_version, %{
                 story_id: story.id,
                 sequence_id: seq2.id,
                 content: "Act two v1."
               })
               |> Ash.run_action()

      assert act_two_v1.version_number == 1
      assert act_two_v1.sequence_id == seq2.id
    end
  end

  describe "set_weights action" do
    test "updates weights on a sequence piece", %{story: story, seq1: seq1} do
      {:ok, piece} =
        Storybox.Stories.SequencePiece
        |> Ash.Changeset.for_create(:create, %{
          story_id: story.id,
          sequence_id: seq1.id,
          content_uri: Storybox.Storage.uri_for_sequence_piece(story.id, seq1.id, 1),
          version_number: 1
        })
        |> Ash.create()

      assert {:ok, updated} =
               piece
               |> Ash.Changeset.for_update(:set_weights, %{weights: %{"preference" => 0.9}})
               |> Ash.update()

      assert updated.weights == %{"preference" => 0.9}
    end
  end
end
