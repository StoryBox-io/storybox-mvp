defmodule Storybox.Stories.CharacterThroughlineViewVersion do
  use Ash.Resource,
    domain: Storybox.Stories,
    data_layer: AshPostgres.DataLayer

  require Ash.Query

  postgres do
    table "character_throughline_view_versions"
    repo Storybox.Repo

    # The derived name exceeds Postgres' 63-character identifier limit.
    identity_index_names unique_version_per_view:
                           "char_throughline_vv_unique_version_per_view_index"
  end

  attributes do
    uuid_primary_key :id

    attribute :version_number, :integer, allow_nil?: false, public?: true

    create_timestamp :inserted_at
  end

  relationships do
    belongs_to :character_throughline_view, Storybox.Stories.CharacterThroughlineView,
      allow_nil?: false,
      public?: true

    has_many :segments, Storybox.Stories.Segment,
      destination_attribute: :view_version_id,
      filter: [view_version_type: :character_throughline_vv],
      public?: true
  end

  identities do
    identity :unique_version_per_view, [:character_throughline_view_id, :version_number]
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:character_throughline_view_id, :version_number]
    end

    action :cut, :struct do
      constraints instance_of: Storybox.Stories.CharacterThroughlineViewVersion
      argument :character_throughline_view_id, :uuid, allow_nil?: false

      # Optional explicit segment list. When supplied, these exact segments are
      # written through at position 1..N (each map: %{"pin_id" => uuid | nil,
      # "pin_type" => atom | nil, "pin_version_at_creation" => integer | nil}),
      # which is how a caller deliberately re-pins an older ThroughlinePiece
      # version. When absent, the character's latest ThroughlinePiece is
      # resolved and pinned at position 1.
      argument :segments, {:array, :map}, allow_nil?: true, default: nil

      run fn input, _context ->
        view_id = input.arguments.character_throughline_view_id

        view =
          Storybox.Stories.CharacterThroughlineView
          |> Ash.Query.filter(id == ^view_id)
          |> Ash.read_one!(authorize?: false)

        existing_versions =
          Storybox.Stories.CharacterThroughlineViewVersion
          |> Ash.Query.filter(character_throughline_view_id == ^view_id)
          |> Ash.read!(authorize?: false)

        next_version_number =
          existing_versions
          |> Enum.map(& &1.version_number)
          |> Enum.max(fn -> 0 end)
          |> Kernel.+(1)

        {:ok, vv} =
          Storybox.Stories.CharacterThroughlineViewVersion
          |> Ash.Changeset.for_create(:create, %{
            character_throughline_view_id: view_id,
            version_number: next_version_number
          })
          |> Ash.create(authorize?: false)

        vv.id
        |> segment_attrs(Map.get(input.arguments, :segments), view)
        |> Enum.each(fn attrs ->
          Storybox.Stories.Segment
          |> Ash.Changeset.for_create(:create, attrs)
          |> Ash.create!(authorize?: false)
        end)

        {:ok, vv}
      end
    end
  end

  # Explicit segments: written through as given, at position 1..N.
  defp segment_attrs(vv_id, segments, _view) when is_list(segments) do
    segments
    |> Enum.with_index(1)
    |> Enum.map(fn {segment, position} ->
      base = %{
        view_version_id: vv_id,
        view_version_type: :character_throughline_vv,
        position: position
      }

      case Map.get(segment, "pin_id") do
        nil ->
          base

        pin_id ->
          Map.merge(base, %{
            pin_id: pin_id,
            pin_type: Map.get(segment, "pin_type"),
            pin_version_at_creation: Map.get(segment, "pin_version_at_creation")
          })
      end
    end)
  end

  # No explicit segments: pin the character's latest ThroughlinePiece, if any.
  defp segment_attrs(vv_id, nil, view) do
    latest_piece =
      Storybox.Stories.ThroughlinePiece
      |> Ash.Query.filter(character_id == ^view.character_id)
      |> Ash.Query.sort(version_number: :desc)
      |> Ash.Query.limit(1)
      |> Ash.read!(authorize?: false)
      |> List.first()

    case latest_piece do
      nil ->
        []

      piece ->
        [
          %{
            view_version_id: vv_id,
            view_version_type: :character_throughline_vv,
            position: 1,
            pin_id: piece.id,
            pin_type: :throughline_piece,
            pin_version_at_creation: piece.version_number
          }
        ]
    end
  end
end
