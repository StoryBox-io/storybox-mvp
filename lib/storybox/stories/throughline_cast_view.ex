defmodule Storybox.Stories.ThroughlineCastView do
  use Ash.Resource,
    domain: Storybox.Stories,
    data_layer: AshPostgres.DataLayer

  require Ash.Query

  postgres do
    table "throughline_cast_views"
    repo Storybox.Repo
  end

  attributes do
    uuid_primary_key :id

    create_timestamp :inserted_at
  end

  relationships do
    belongs_to :story, Storybox.Stories.Story, allow_nil?: false, public?: true

    has_many :throughline_cast_view_versions,
             Storybox.Stories.ThroughlineCastViewVersion,
             public?: true
  end

  identities do
    identity :unique_story, [:story_id]
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:story_id]
    end

    action :ensure_for_story, :struct do
      constraints instance_of: Storybox.Stories.ThroughlineCastView
      argument :story_id, :uuid, allow_nil?: false

      run fn input, _context ->
        story_id = input.arguments.story_id

        case Storybox.Stories.ThroughlineCastView
             |> Ash.Query.filter(story_id == ^story_id)
             |> Ash.read_one!(authorize?: false) do
          nil ->
            Storybox.Stories.ThroughlineCastView
            |> Ash.Changeset.for_create(:create, %{story_id: story_id})
            |> Ash.create(authorize?: false)

          existing ->
            {:ok, existing}
        end
      end
    end

    # Place a character's through-line view in the cast stack at `position`,
    # shifting the rest down. The character must already have a through-line
    # view with at least one version — the cast stack pins arcs, it does not
    # create them.
    action :insert_entry, :struct do
      constraints instance_of: Storybox.Stories.ThroughlineCastViewVersion
      argument :throughline_cast_view_id, :uuid, allow_nil?: false
      argument :character_id, :uuid, allow_nil?: false
      argument :position, :integer, allow_nil?: false

      run fn input, _context ->
        cast_view_id = input.arguments.throughline_cast_view_id
        character_id = input.arguments.character_id
        position = input.arguments.position

        cast_view =
          Storybox.Stories.ThroughlineCastView
          |> Ash.Query.filter(id == ^cast_view_id)
          |> Ash.read_one!(authorize?: false)

        entries = Storybox.Stories.ThroughlineCastView.ordered_entries(cast_view_id)

        with {:ok, char_vv} <- latest_character_vv(cast_view.story_id, character_id),
             :ok <- refute_present(entries, character_id),
             :ok <- check_range(position, length(entries) + 1) do
          entries
          |> Enum.map(& &1.pin)
          |> List.insert_at(position - 1, vv_pin(char_vv))
          |> cut(cast_view_id)
        end
      end
    end

    # Move an entry already in the stack to `new_position`. The entry's pin is
    # carried across untouched — a reorder says nothing about which version of
    # the character's arc is pinned, only where it sits.
    action :reorder_entry, :struct do
      constraints instance_of: Storybox.Stories.ThroughlineCastViewVersion
      argument :throughline_cast_view_id, :uuid, allow_nil?: false
      argument :character_id, :uuid, allow_nil?: false
      argument :new_position, :integer, allow_nil?: false

      run fn input, _context ->
        cast_view_id = input.arguments.throughline_cast_view_id
        character_id = input.arguments.character_id
        new_position = input.arguments.new_position

        entries = Storybox.Stories.ThroughlineCastView.ordered_entries(cast_view_id)
        target = Enum.find(entries, &(&1.character_id == character_id))

        with :ok <- require_present(target, character_id),
             :ok <- check_range(new_position, length(entries)) do
          entries
          |> Enum.reject(&(&1.character_id == character_id))
          |> Enum.map(& &1.pin)
          |> List.insert_at(new_position - 1, target.pin)
          |> cut(cast_view_id)
        end
      end
    end

    # Drop an entry from the stack, closing the gap. Only the cast stack's
    # segment list changes: the character's own through-line view, its versions
    # and its pieces are untouched, so a later insert picks that lineage back up.
    action :remove_entry, :struct do
      constraints instance_of: Storybox.Stories.ThroughlineCastViewVersion
      argument :throughline_cast_view_id, :uuid, allow_nil?: false
      argument :character_id, :uuid, allow_nil?: false

      run fn input, _context ->
        cast_view_id = input.arguments.throughline_cast_view_id
        character_id = input.arguments.character_id

        entries = Storybox.Stories.ThroughlineCastView.ordered_entries(cast_view_id)
        target = Enum.find(entries, &(&1.character_id == character_id))

        with :ok <- require_present(target, character_id) do
          entries
          |> Enum.reject(&(&1.character_id == character_id))
          |> Enum.map(& &1.pin)
          |> cut(cast_view_id)
        end
      end
    end
  end

  @doc """
  The cast stack as it currently stands: one entry per segment on the view's
  latest version, in position order, shaped `%{character_id: uuid | nil, pin:
  pin_map}`.

  Position in this list *is* evaluation priority. `pin` is a cut-ready segment
  map, so a caller can rearrange the list and hand it straight back to
  `ThroughlineCastViewVersion`'s `:cut`. Returns `[]` when the view has no
  version yet.
  """
  def ordered_entries(cast_view_id) do
    case latest_version(cast_view_id) do
      nil -> []
      latest -> entries_for_version(latest.id)
    end
  end

  @doc """
  `ordered_entries/1`'s shape for one specific cast view version, so a caller
  can read back the stack a given op produced rather than the current head.
  """
  def entries_for_version(cast_view_version_id) do
    view_version_type = :throughline_cast_vv

    segments =
      Storybox.Stories.Segment
      |> Ash.Query.filter(
        view_version_id == ^cast_view_version_id and view_version_type == ^view_version_type
      )
      |> Ash.Query.sort(:position)
      |> Ash.read!(authorize?: false)

    character_ids = character_ids_by_pin(segments)

    Enum.map(segments, fn seg ->
      %{character_id: Map.get(character_ids, seg.pin_id), pin: segment_pin(seg)}
    end)
  end

  defp latest_version(cast_view_id) do
    Storybox.Stories.ThroughlineCastViewVersion
    |> Ash.Query.filter(throughline_cast_view_id == ^cast_view_id)
    |> Ash.Query.sort(version_number: :desc)
    |> Ash.Query.limit(1)
    |> Ash.read!(authorize?: false)
    |> List.first()
  end

  # pin_id (a CharacterThroughlineViewVersion) => the character it belongs to,
  # resolved through that version's view. Segments with no pin are absent.
  defp character_ids_by_pin(segments) do
    pin_ids = segments |> Enum.map(& &1.pin_id) |> Enum.reject(&is_nil/1)

    char_vvs =
      Storybox.Stories.CharacterThroughlineViewVersion
      |> Ash.Query.filter(id in ^pin_ids)
      |> Ash.read!(authorize?: false)

    view_ids = Enum.map(char_vvs, & &1.character_throughline_view_id)

    characters_by_view =
      Storybox.Stories.CharacterThroughlineView
      |> Ash.Query.filter(id in ^view_ids)
      |> Ash.read!(authorize?: false)
      |> Map.new(fn view -> {view.id, view.character_id} end)

    Map.new(char_vvs, fn vv ->
      {vv.id, Map.get(characters_by_view, vv.character_throughline_view_id)}
    end)
  end

  # The lineage head of the character's through-line view — what an insert pins.
  defp latest_character_vv(story_id, character_id) do
    char_view =
      Storybox.Stories.CharacterThroughlineView
      |> Ash.Query.filter(story_id == ^story_id and character_id == ^character_id)
      |> Ash.read_one!(authorize?: false)

    latest =
      case char_view do
        nil ->
          nil

        view ->
          Storybox.Stories.CharacterThroughlineViewVersion
          |> Ash.Query.filter(character_throughline_view_id == ^view.id)
          |> Ash.Query.sort(version_number: :desc)
          |> Ash.Query.limit(1)
          |> Ash.read!(authorize?: false)
          |> List.first()
      end

    case latest do
      nil -> {:error, "No through-line view for character #{character_id}"}
      vv -> {:ok, vv}
    end
  end

  defp refute_present(entries, character_id) do
    if Enum.any?(entries, &(&1.character_id == character_id)),
      do: {:error, "Character #{character_id} is already in the cast"},
      else: :ok
  end

  defp require_present(nil, character_id),
    do: {:error, "Character #{character_id} is not in the cast"}

  defp require_present(_target, _character_id), do: :ok

  # Positions are contiguous 1..N, so an op naming anything outside the range it
  # is allowed to land in is rejected rather than clamped.
  defp check_range(position, max) do
    if position >= 1 and position <= max,
      do: :ok,
      else: {:error, "Position #{position} is out of range (1..#{max})"}
  end

  defp cut(pins, cast_view_id) do
    Storybox.Stories.ThroughlineCastViewVersion
    |> Ash.ActionInput.for_action(:cut, %{
      throughline_cast_view_id: cast_view_id,
      segments: pins
    })
    |> Ash.run_action(authorize?: false)
  end

  defp vv_pin(vv) do
    %{
      "pin_id" => vv.id,
      "pin_type" => "throughline_vv",
      "pin_version_at_creation" => vv.version_number
    }
  end

  defp segment_pin(seg) do
    %{
      "pin_id" => seg.pin_id,
      "pin_type" => seg.pin_type && Atom.to_string(seg.pin_type),
      "pin_version_at_creation" => seg.pin_version_at_creation
    }
  end
end
