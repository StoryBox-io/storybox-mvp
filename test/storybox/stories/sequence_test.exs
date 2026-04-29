defmodule Storybox.Stories.SequenceTest do
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

    {:ok, story_a} =
      Storybox.Stories.Story
      |> Ash.Changeset.for_create(:create, %{title: "Little Witch", user_id: user.id})
      |> Ash.create()

    {:ok, story_b} =
      Storybox.Stories.Story
      |> Ash.Changeset.for_create(:create, %{title: "The Wanderer", user_id: user.id})
      |> Ash.create()

    %{story_a: story_a, story_b: story_b}
  end

  describe "create" do
    test "creates a sequence with name, slug, and story_id", %{story_a: story_a} do
      assert {:ok, sequence} =
               Storybox.Stories.Sequence
               |> Ash.Changeset.for_create(:create, %{
                 name: "Prologue",
                 slug: "prologue",
                 story_id: story_a.id
               })
               |> Ash.create()

      assert sequence.name == "Prologue"
      assert sequence.slug == "prologue"
      assert sequence.story_id == story_a.id
    end

    test "fails without a story_id" do
      assert {:error, %Ash.Error.Invalid{}} =
               Storybox.Stories.Sequence
               |> Ash.Changeset.for_create(:create, %{name: "Prologue", slug: "prologue"})
               |> Ash.create()
    end

    test "fails without a name", %{story_a: story_a} do
      assert {:error, %Ash.Error.Invalid{}} =
               Storybox.Stories.Sequence
               |> Ash.Changeset.for_create(:create, %{slug: "prologue", story_id: story_a.id})
               |> Ash.create()
    end

    test "fails without a slug", %{story_a: story_a} do
      assert {:error, %Ash.Error.Invalid{}} =
               Storybox.Stories.Sequence
               |> Ash.Changeset.for_create(:create, %{name: "Prologue", story_id: story_a.id})
               |> Ash.create()
    end

    test "rejects a duplicate slug within the same story", %{story_a: story_a} do
      {:ok, _} =
        Storybox.Stories.Sequence
        |> Ash.Changeset.for_create(:create, %{
          name: "Prologue",
          slug: "prologue",
          story_id: story_a.id
        })
        |> Ash.create()

      assert {:error, %Ash.Error.Invalid{}} =
               Storybox.Stories.Sequence
               |> Ash.Changeset.for_create(:create, %{
                 name: "Prologue Redux",
                 slug: "prologue",
                 story_id: story_a.id
               })
               |> Ash.create()
    end

    test "allows the same slug across different stories", %{
      story_a: story_a,
      story_b: story_b
    } do
      assert {:ok, sequence_a} =
               Storybox.Stories.Sequence
               |> Ash.Changeset.for_create(:create, %{
                 name: "Prologue",
                 slug: "prologue",
                 story_id: story_a.id
               })
               |> Ash.create()

      assert {:ok, sequence_b} =
               Storybox.Stories.Sequence
               |> Ash.Changeset.for_create(:create, %{
                 name: "Prologue",
                 slug: "prologue",
                 story_id: story_b.id
               })
               |> Ash.create()

      assert sequence_a.story_id == story_a.id
      assert sequence_b.story_id == story_b.id
      assert sequence_a.id != sequence_b.id
    end
  end

  describe "read" do
    test "returns sequences belonging to a story and excludes other stories' sequences", %{
      story_a: story_a,
      story_b: story_b
    } do
      {:ok, _} =
        Storybox.Stories.Sequence
        |> Ash.Changeset.for_create(:create, %{
          name: "Prologue",
          slug: "prologue",
          story_id: story_a.id
        })
        |> Ash.create()

      {:ok, _} =
        Storybox.Stories.Sequence
        |> Ash.Changeset.for_create(:create, %{
          name: "Cottage",
          slug: "cottage",
          story_id: story_a.id
        })
        |> Ash.create()

      {:ok, _} =
        Storybox.Stories.Sequence
        |> Ash.Changeset.for_create(:create, %{
          name: "Prologue",
          slug: "prologue",
          story_id: story_b.id
        })
        |> Ash.create()

      {:ok, story_a_loaded} = Ash.load(story_a, :sequences)

      sequence_names = story_a_loaded.sequences |> Enum.map(& &1.name) |> Enum.sort()
      assert sequence_names == ["Cottage", "Prologue"]
      assert Enum.all?(story_a_loaded.sequences, &(&1.story_id == story_a.id))
    end
  end

  describe "update" do
    test "changes name and leaves slug unchanged", %{story_a: story_a} do
      {:ok, sequence} =
        Storybox.Stories.Sequence
        |> Ash.Changeset.for_create(:create, %{
          name: "Prologue",
          slug: "prologue",
          story_id: story_a.id
        })
        |> Ash.create()

      assert {:ok, updated} =
               sequence
               |> Ash.Changeset.for_update(:update, %{name: "Cold Open"})
               |> Ash.update()

      assert updated.name == "Cold Open"
      assert updated.slug == "prologue"
    end

    test "rejects attempts to change slug via the update action", %{story_a: story_a} do
      {:ok, sequence} =
        Storybox.Stories.Sequence
        |> Ash.Changeset.for_create(:create, %{
          name: "Prologue",
          slug: "prologue",
          story_id: story_a.id
        })
        |> Ash.create()

      assert {:error, %Ash.Error.Invalid{}} =
               sequence
               |> Ash.Changeset.for_update(:update, %{name: "Cold Open", slug: "renamed"})
               |> Ash.update()

      {:ok, reloaded} = Ash.get(Storybox.Stories.Sequence, sequence.id)
      assert reloaded.slug == "prologue"
    end
  end

  describe "destroy" do
    test "removes the sequence from the database", %{story_a: story_a} do
      {:ok, sequence} =
        Storybox.Stories.Sequence
        |> Ash.Changeset.for_create(:create, %{
          name: "Prologue",
          slug: "prologue",
          story_id: story_a.id
        })
        |> Ash.create()

      :ok =
        sequence
        |> Ash.Changeset.for_destroy(:destroy)
        |> Ash.destroy!()

      assert {:error, %Ash.Error.Invalid{}} = Ash.get(Storybox.Stories.Sequence, sequence.id)

      {:ok, all} = Ash.read(Storybox.Stories.Sequence)
      refute Enum.any?(all, &(&1.id == sequence.id))
    end
  end
end
