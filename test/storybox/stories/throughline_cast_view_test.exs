defmodule Storybox.Stories.ThroughlineCastViewTest do
  use Storybox.DataCase

  require Ash.Query

  setup do
    {:ok, user} =
      Storybox.Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "tcv_test@example.com",
        password: "password123!",
        password_confirmation: "password123!"
      })
      |> Ash.create()

    {:ok, story} =
      Storybox.Stories.Story
      |> Ash.Changeset.for_create(:create, %{title: "Test Story", user_id: user.id})
      |> Ash.create()

    %{story: story}
  end

  describe "ensure_for_story" do
    test "creates the view on first call", %{story: story} do
      assert {:ok, view} =
               Storybox.Stories.ThroughlineCastView
               |> Ash.ActionInput.for_action(:ensure_for_story, %{story_id: story.id})
               |> Ash.run_action()

      assert view.story_id == story.id
    end

    test "is idempotent — a second call returns the same record", %{story: story} do
      {:ok, first} =
        Storybox.Stories.ThroughlineCastView
        |> Ash.ActionInput.for_action(:ensure_for_story, %{story_id: story.id})
        |> Ash.run_action()

      {:ok, second} =
        Storybox.Stories.ThroughlineCastView
        |> Ash.ActionInput.for_action(:ensure_for_story, %{story_id: story.id})
        |> Ash.run_action()

      assert first.id == second.id

      all =
        Storybox.Stories.ThroughlineCastView
        |> Ash.Query.filter(story_id == ^story.id)
        |> Ash.read!(authorize?: false)

      assert length(all) == 1
    end
  end

  describe "create" do
    test "a duplicate story is rejected", %{story: story} do
      {:ok, _view} =
        Storybox.Stories.ThroughlineCastView
        |> Ash.Changeset.for_create(:create, %{story_id: story.id})
        |> Ash.create()

      assert {:error, %Ash.Error.Invalid{}} =
               Storybox.Stories.ThroughlineCastView
               |> Ash.Changeset.for_create(:create, %{story_id: story.id})
               |> Ash.create()
    end
  end

  # Writes a character with a through-line arc: the piece, the per-character
  # view, and one cut on it — the lineage head the cast stack pins.
  defp character_with_arc(story, name) do
    {:ok, character} =
      Storybox.Stories.Character
      |> Ash.Changeset.for_create(:create, %{name: name, story_id: story.id})
      |> Ash.create(authorize?: false)

    {:ok, _piece} =
      Storybox.Stories.ThroughlinePiece
      |> Ash.ActionInput.for_action(:create_version, %{
        story_id: story.id,
        character_id: character.id,
        content: "#{name}'s arc."
      })
      |> Ash.run_action(authorize?: false)

    {:ok, char_view} =
      Storybox.Stories.CharacterThroughlineView
      |> Ash.ActionInput.for_action(:ensure_for_story_character, %{
        story_id: story.id,
        character_id: character.id
      })
      |> Ash.run_action(authorize?: false)

    {:ok, char_vv} =
      Storybox.Stories.CharacterThroughlineViewVersion
      |> Ash.ActionInput.for_action(:cut, %{character_throughline_view_id: char_view.id})
      |> Ash.run_action(authorize?: false)

    %{character: character, char_view: char_view, char_vv: char_vv}
  end

  defp cast_view!(story) do
    {:ok, view} =
      Storybox.Stories.ThroughlineCastView
      |> Ash.ActionInput.for_action(:ensure_for_story, %{story_id: story.id})
      |> Ash.run_action(authorize?: false)

    view
  end

  defp op(cast_view, action, args) do
    Storybox.Stories.ThroughlineCastView
    |> Ash.ActionInput.for_action(
      action,
      Map.merge(%{throughline_cast_view_id: cast_view.id}, args)
    )
    |> Ash.run_action(authorize?: false)
  end

  defp insert!(cast_view, character, position) do
    {:ok, vv} = op(cast_view, :insert_entry, %{character_id: character.id, position: position})
    vv
  end

  defp character_order(cast_view) do
    cast_view.id
    |> Storybox.Stories.ThroughlineCastView.ordered_entries()
    |> Enum.map(& &1.character_id)
  end

  describe "insert_entry" do
    test "places a character at the requested position and shifts the rest down", %{story: story} do
      cast_view = cast_view!(story)
      a = character_with_arc(story, "A")
      b = character_with_arc(story, "B")
      c = character_with_arc(story, "C")

      insert!(cast_view, a.character, 1)
      insert!(cast_view, b.character, 2)
      insert!(cast_view, c.character, 2)

      assert character_order(cast_view) == [a.character.id, c.character.id, b.character.id]
    end

    test "pins the character's lineage head", %{story: story} do
      cast_view = cast_view!(story)
      a = character_with_arc(story, "A")

      insert!(cast_view, a.character, 1)

      assert [%{pin: pin}] = Storybox.Stories.ThroughlineCastView.ordered_entries(cast_view.id)
      assert pin["pin_id"] == a.char_vv.id
      assert pin["pin_type"] == "throughline_vv"
      assert pin["pin_version_at_creation"] == a.char_vv.version_number
    end

    test "rejects a position past the end rather than clamping it", %{story: story} do
      cast_view = cast_view!(story)
      a = character_with_arc(story, "A")
      b = character_with_arc(story, "B")

      insert!(cast_view, a.character, 1)

      assert {:error, _} =
               op(cast_view, :insert_entry, %{character_id: b.character.id, position: 3})

      assert character_order(cast_view) == [a.character.id]
    end

    test "rejects a character with no through-line view", %{story: story} do
      cast_view = cast_view!(story)

      {:ok, bare} =
        Storybox.Stories.Character
        |> Ash.Changeset.for_create(:create, %{name: "Bare", story_id: story.id})
        |> Ash.create(authorize?: false)

      assert {:error, _} = op(cast_view, :insert_entry, %{character_id: bare.id, position: 1})
      assert character_order(cast_view) == []
    end

    test "rejects a character already in the cast", %{story: story} do
      cast_view = cast_view!(story)
      a = character_with_arc(story, "A")

      insert!(cast_view, a.character, 1)

      assert {:error, _} =
               op(cast_view, :insert_entry, %{character_id: a.character.id, position: 1})

      assert character_order(cast_view) == [a.character.id]
    end
  end

  describe "reorder_entry" do
    setup %{story: story} do
      cast_view = cast_view!(story)
      a = character_with_arc(story, "A")
      b = character_with_arc(story, "B")
      c = character_with_arc(story, "C")

      insert!(cast_view, a.character, 1)
      insert!(cast_view, b.character, 2)
      insert!(cast_view, c.character, 3)

      %{cast_view: cast_view, a: a, b: b, c: c}
    end

    test "moves an entry and leaves the others' relative order intact", ctx do
      {:ok, _vv} =
        op(ctx.cast_view, :reorder_entry, %{character_id: ctx.c.character.id, new_position: 1})

      assert character_order(ctx.cast_view) == [
               ctx.c.character.id,
               ctx.a.character.id,
               ctx.b.character.id
             ]
    end

    test "carries the moved entry's pin across untouched", ctx do
      {:ok, vv} =
        op(ctx.cast_view, :reorder_entry, %{character_id: ctx.a.character.id, new_position: 3})

      entries = Storybox.Stories.ThroughlineCastView.entries_for_version(vv.id)
      moved = Enum.find(entries, &(&1.character_id == ctx.a.character.id))

      assert moved.pin["pin_id"] == ctx.a.char_vv.id
    end

    test "rejects an out-of-range new_position", ctx do
      assert {:error, _} =
               op(ctx.cast_view, :reorder_entry, %{
                 character_id: ctx.a.character.id,
                 new_position: 4
               })

      assert character_order(ctx.cast_view) == [
               ctx.a.character.id,
               ctx.b.character.id,
               ctx.c.character.id
             ]
    end

    test "rejects a character not currently in the cast", %{cast_view: cast_view, story: story} do
      outsider = character_with_arc(story, "Outsider")

      assert {:error, _} =
               op(cast_view, :reorder_entry, %{
                 character_id: outsider.character.id,
                 new_position: 1
               })
    end
  end

  describe "remove_entry" do
    setup %{story: story} do
      cast_view = cast_view!(story)
      a = character_with_arc(story, "A")
      b = character_with_arc(story, "B")
      c = character_with_arc(story, "C")

      insert!(cast_view, a.character, 1)
      insert!(cast_view, b.character, 2)
      insert!(cast_view, c.character, 3)

      %{cast_view: cast_view, a: a, b: b, c: c}
    end

    test "closes the gap, leaving positions contiguous", ctx do
      {:ok, vv} = op(ctx.cast_view, :remove_entry, %{character_id: ctx.b.character.id})

      assert character_order(ctx.cast_view) == [ctx.a.character.id, ctx.c.character.id]

      positions =
        Storybox.Stories.Segment
        |> Ash.Query.filter(view_version_id == ^vv.id)
        |> Ash.Query.sort(:position)
        |> Ash.read!(authorize?: false)
        |> Enum.map(& &1.position)

      assert positions == [1, 2]
    end

    test "leaves the character's own view and versions untouched", ctx do
      {:ok, _vv} = op(ctx.cast_view, :remove_entry, %{character_id: ctx.b.character.id})

      char_view_id = ctx.b.char_view.id

      assert Storybox.Stories.CharacterThroughlineView
             |> Ash.Query.filter(id == ^char_view_id)
             |> Ash.read_one!(authorize?: false)

      versions =
        Storybox.Stories.CharacterThroughlineViewVersion
        |> Ash.Query.filter(character_throughline_view_id == ^char_view_id)
        |> Ash.read!(authorize?: false)

      assert length(versions) == 1
    end

    test "removing the last entry leaves an empty version", ctx do
      Enum.each([ctx.a, ctx.b, ctx.c], fn entry ->
        {:ok, _} = op(ctx.cast_view, :remove_entry, %{character_id: entry.character.id})
      end)

      assert character_order(ctx.cast_view) == []
    end

    test "rejects a character not currently in the cast", %{cast_view: cast_view, story: story} do
      outsider = character_with_arc(story, "Outsider")

      assert {:error, _} = op(cast_view, :remove_entry, %{character_id: outsider.character.id})
    end

    test "remove then re-insert reuses the character's existing view and lineage head", ctx do
      {:ok, _} = op(ctx.cast_view, :remove_entry, %{character_id: ctx.b.character.id})
      insert!(ctx.cast_view, ctx.b.character, 1)

      character_id = ctx.b.character.id

      views =
        Storybox.Stories.CharacterThroughlineView
        |> Ash.Query.filter(character_id == ^character_id)
        |> Ash.read!(authorize?: false)

      assert length(views) == 1

      entries = Storybox.Stories.ThroughlineCastView.ordered_entries(ctx.cast_view.id)
      reinserted = Enum.find(entries, &(&1.character_id == character_id))

      assert reinserted.pin["pin_id"] == ctx.b.char_vv.id

      assert character_order(ctx.cast_view) == [
               character_id,
               ctx.a.character.id,
               ctx.c.character.id
             ]
    end
  end

  describe "versioning" do
    test "each op cuts a new version and leaves prior versions' segments intact", %{story: story} do
      cast_view = cast_view!(story)
      a = character_with_arc(story, "A")
      b = character_with_arc(story, "B")

      first = insert!(cast_view, a.character, 1)
      second = insert!(cast_view, b.character, 1)

      assert first.version_number == 1
      assert second.version_number == 2

      # The first version still holds A alone, in the order it was cut with.
      assert Storybox.Stories.ThroughlineCastView.entries_for_version(first.id)
             |> Enum.map(& &1.character_id) == [a.character.id]

      assert Storybox.Stories.ThroughlineCastView.entries_for_version(second.id)
             |> Enum.map(& &1.character_id) == [b.character.id, a.character.id]
    end
  end
end
