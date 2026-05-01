defmodule Storybox.Stories.SynopsisPieceTest do
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
        name: "Prologue",
        slug: "prologue",
        story_id: story.id
      })
      |> Ash.create()

    {:ok, seq2} =
      Storybox.Stories.Sequence
      |> Ash.Changeset.for_create(:create, %{
        name: "Forest",
        slug: "forest",
        story_id: story.id
      })
      |> Ash.create()

    %{story: story, seq1: seq1, seq2: seq2}
  end

  describe "create" do
    test "creates a synopsis piece with all required fields", %{
      story: story,
      seq1: seq1
    } do
      uri = Storybox.Storage.uri_for_synopsis_piece(story.id, seq1.id, 1)

      assert {:ok, piece} =
               Storybox.Stories.SynopsisPiece
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
    end

    test "fails without story_id", %{seq1: seq1} do
      assert {:error, %Ash.Error.Invalid{}} =
               Storybox.Stories.SynopsisPiece
               |> Ash.Changeset.for_create(:create, %{
                 sequence_id: seq1.id,
                 content_uri: "storybox://stories/x/sequences/y/synopsis/v1.fountain",
                 version_number: 1
               })
               |> Ash.create()
    end

    test "fails without sequence_id", %{story: story} do
      assert {:error, %Ash.Error.Invalid{}} =
               Storybox.Stories.SynopsisPiece
               |> Ash.Changeset.for_create(:create, %{
                 story_id: story.id,
                 content_uri: "storybox://stories/x/sequences/y/synopsis/v1.fountain",
                 version_number: 1
               })
               |> Ash.create()
    end

    test "fails without content_uri", %{story: story, seq1: seq1} do
      assert {:error, %Ash.Error.Invalid{}} =
               Storybox.Stories.SynopsisPiece
               |> Ash.Changeset.for_create(:create, %{
                 story_id: story.id,
                 sequence_id: seq1.id,
                 version_number: 1
               })
               |> Ash.create()
    end

    test "fails without version_number", %{story: story, seq1: seq1} do
      assert {:error, %Ash.Error.Invalid{}} =
               Storybox.Stories.SynopsisPiece
               |> Ash.Changeset.for_create(:create, %{
                 story_id: story.id,
                 sequence_id: seq1.id,
                 content_uri: "storybox://stories/x/sequences/y/synopsis/v1.fountain"
               })
               |> Ash.create()
    end
  end

  describe "Story.synopsis_pieces association" do
    test "returns all synopsis pieces for the story", %{story: story, seq1: seq1, seq2: seq2} do
      uri1 = Storybox.Storage.uri_for_synopsis_piece(story.id, seq1.id, 1)
      uri2 = Storybox.Storage.uri_for_synopsis_piece(story.id, seq2.id, 1)

      {:ok, _} =
        Storybox.Stories.SynopsisPiece
        |> Ash.Changeset.for_create(:create, %{
          story_id: story.id,
          sequence_id: seq1.id,
          content_uri: uri1,
          version_number: 1
        })
        |> Ash.create()

      {:ok, _} =
        Storybox.Stories.SynopsisPiece
        |> Ash.Changeset.for_create(:create, %{
          story_id: story.id,
          sequence_id: seq2.id,
          content_uri: uri2,
          version_number: 1
        })
        |> Ash.create()

      {:ok, loaded} = Ash.load(story, :synopsis_pieces)
      assert length(loaded.synopsis_pieces) == 2
      assert Enum.all?(loaded.synopsis_pieces, &(&1.story_id == story.id))
    end
  end

  describe "create_version action" do
    test "creates SEQ1-v1 with version_number 1 and correct URI", %{
      story: story,
      seq1: seq1
    } do
      assert {:ok, piece} =
               Storybox.Stories.SynopsisPiece
               |> Ash.ActionInput.for_action(:create_version, %{
                 story_id: story.id,
                 sequence_id: seq1.id,
                 content: "The prologue begins."
               })
               |> Ash.run_action()

      assert piece.version_number == 1
      assert piece.sequence_id == seq1.id

      assert piece.content_uri ==
               Storybox.Storage.uri_for_synopsis_piece(story.id, seq1.id, 1)
    end

    test "increments version_number for SEQ1 on second call", %{story: story, seq1: seq1} do
      {:ok, _} =
        Storybox.Stories.SynopsisPiece
        |> Ash.ActionInput.for_action(:create_version, %{
          story_id: story.id,
          sequence_id: seq1.id,
          content: "Draft one."
        })
        |> Ash.run_action()

      assert {:ok, v2} =
               Storybox.Stories.SynopsisPiece
               |> Ash.ActionInput.for_action(:create_version, %{
                 story_id: story.id,
                 sequence_id: seq1.id,
                 content: "Draft two."
               })
               |> Ash.run_action()

      assert v2.version_number == 2
    end

    test "SEQ2 version counter is independent of SEQ1", %{
      story: story,
      seq1: seq1,
      seq2: seq2
    } do
      {:ok, _} =
        Storybox.Stories.SynopsisPiece
        |> Ash.ActionInput.for_action(:create_version, %{
          story_id: story.id,
          sequence_id: seq1.id,
          content: "Prologue v1."
        })
        |> Ash.run_action()

      {:ok, _} =
        Storybox.Stories.SynopsisPiece
        |> Ash.ActionInput.for_action(:create_version, %{
          story_id: story.id,
          sequence_id: seq1.id,
          content: "Prologue v2."
        })
        |> Ash.run_action()

      assert {:ok, forest_v1} =
               Storybox.Stories.SynopsisPiece
               |> Ash.ActionInput.for_action(:create_version, %{
                 story_id: story.id,
                 sequence_id: seq2.id,
                 content: "Forest v1."
               })
               |> Ash.run_action()

      assert forest_v1.version_number == 1
      assert forest_v1.sequence_id == seq2.id
    end
  end
end
