defmodule Storybox.Stories.Segment do
  use Ash.Resource,
    domain: Storybox.Stories,
    data_layer: AshPostgres.DataLayer

  require Ash.Query

  @view_version_types [
    :synopsis_vv,
    :treatment_vv,
    :script_vv,
    :sequence_vv,
    :story_script_vv,
    :character_vv,
    :world_vv
  ]

  @piece_pin_types [
    :synopsis_piece,
    :sequence_piece,
    :script_piece,
    :character_piece,
    :world_piece
  ]

  @pin_types @piece_pin_types ++ @view_version_types

  postgres do
    table "segments"
    repo Storybox.Repo

    check_constraints do
      check_constraint :pin_id, "segments_pin_complete_or_empty",
        check:
          "(pin_id IS NULL AND pin_type IS NULL AND pin_version_at_creation IS NULL) OR " <>
            "(pin_id IS NOT NULL AND pin_type IS NOT NULL AND pin_version_at_creation IS NOT NULL)",
        message: "pin_id, pin_type, and pin_version_at_creation must all be set or all be null"
    end

    custom_indexes do
      index [:view_version_id, :sequence_id], where: "sequence_id IS NOT NULL"
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :view_version_id, :uuid, allow_nil?: false, public?: true

    attribute :view_version_type, :atom,
      allow_nil?: false,
      public?: true,
      constraints: [one_of: @view_version_types]

    attribute :position, :integer, allow_nil?: false, public?: true

    attribute :pin_id, :uuid, allow_nil?: true, public?: true

    attribute :pin_type, :atom,
      allow_nil?: true,
      public?: true,
      constraints: [one_of: @pin_types]

    attribute :pin_version_at_creation, :integer, allow_nil?: true, public?: true

    create_timestamp :inserted_at
  end

  relationships do
    belongs_to :sequence, Storybox.Stories.Sequence, allow_nil?: true, public?: true
  end

  identities do
    identity :unique_position_per_vv, [:view_version_id, :view_version_type, :position]
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [
        :view_version_id,
        :view_version_type,
        :position,
        :sequence_id,
        :pin_id,
        :pin_type,
        :pin_version_at_creation
      ]

      change fn changeset, _context ->
        pin_id = Ash.Changeset.get_attribute(changeset, :pin_id)
        pin_type = Ash.Changeset.get_attribute(changeset, :pin_type)
        pin_version = Ash.Changeset.get_attribute(changeset, :pin_version_at_creation)

        case {is_nil(pin_id), is_nil(pin_type), is_nil(pin_version)} do
          {true, true, true} ->
            changeset

          {false, false, false} ->
            changeset

          _ ->
            Ash.Changeset.add_error(changeset,
              field: :pin_id,
              message:
                "pin_id, pin_type, and pin_version_at_creation must all be set or all be null"
            )
        end
      end
    end
  end

  @doc """
  Resolves the polymorphic Pin on a Segment.

  Returns `{:resolved, target}` for a pinned Segment (target is the loaded
  Piece or ViewVersion struct, dispatched on `pin_type`), or
  `{:unresolvable, segment}` for a Segment with both `pin_id` and `pin_type`
  null. Raises `ArgumentError` for `pin_type` atoms whose backing resource
  has not yet been built.
  """
  def resolve_pin(%{pin_id: nil, pin_type: nil} = segment) do
    {:unresolvable, segment}
  end

  def resolve_pin(%{pin_id: pin_id, pin_type: pin_type})
      when not is_nil(pin_id) and not is_nil(pin_type) do
    module = pin_module!(pin_type)

    target =
      module
      |> Ash.Query.filter(id == ^pin_id)
      |> Ash.read_one!(authorize?: false)

    {:resolved, target}
  end

  @doc """
  Returns the current latest version_number of the Pin's lineage, or `nil`
  for an unresolvable Segment. Raises `ArgumentError` for `pin_type` atoms
  whose lineage lookup has not yet been implemented.

  Used to compute view-staleness: a Segment is stale when
  `pin_version_at_creation < pin_target_latest_version(segment)`.
  """
  def pin_target_latest_version(%{pin_id: nil}), do: nil

  def pin_target_latest_version(%{pin_type: :script_piece, pin_id: pin_id})
      when not is_nil(pin_id) do
    pinned =
      Storybox.Stories.ScriptPiece
      |> Ash.Query.filter(id == ^pin_id)
      |> Ash.read_one!(authorize?: false)

    Storybox.Stories.ScriptPiece
    |> Ash.Query.filter(script_view_id == ^pinned.script_view_id)
    |> Ash.read!(authorize?: false)
    |> Enum.map(& &1.version_number)
    |> Enum.max(fn -> nil end)
  end

  def pin_target_latest_version(%{pin_type: pin_type}) do
    raise ArgumentError,
          "pin_target_latest_version/1 is not yet implemented for pin_type #{inspect(pin_type)}"
  end

  defp pin_module!(:script_piece), do: Storybox.Stories.ScriptPiece

  defp pin_module!(pin_type) when pin_type in @pin_types do
    raise ArgumentError,
          "resolve_pin/1 is not yet implemented for pin_type #{inspect(pin_type)} — " <>
            "the backing resource has not been built yet (see issues #80, #92, #93, #94, #95, #96, #97, #98, #101)"
  end

  defp pin_module!(other) do
    raise ArgumentError, "unknown pin_type #{inspect(other)}"
  end
end
