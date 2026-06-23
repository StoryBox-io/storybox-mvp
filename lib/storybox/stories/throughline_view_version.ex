defmodule Storybox.Stories.ThroughlineViewVersion do
  use Ash.Resource,
    domain: Storybox.Stories,
    data_layer: AshPostgres.DataLayer

  require Ash.Query

  postgres do
    table "throughline_view_versions"
    repo Storybox.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :version_number, :integer, allow_nil?: false, public?: true

    create_timestamp :inserted_at
  end

  relationships do
    belongs_to :throughline_view, Storybox.Stories.ThroughlineView,
      allow_nil?: false,
      public?: true

    has_many :segments, Storybox.Stories.Segment,
      destination_attribute: :view_version_id,
      filter: [view_version_type: :throughline_vv],
      public?: true
  end

  identities do
    identity :unique_version_per_view, [:throughline_view_id, :version_number]
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:throughline_view_id, :version_number]
    end

    action :cut, :struct do
      constraints instance_of: Storybox.Stories.ThroughlineViewVersion
      argument :throughline_view_id, :uuid, allow_nil?: false

      # Optional explicit segment list. When supplied, these exact, order-free
      # segments are written (each map: %{"pin_id" => uuid | nil, "pin_type" =>
      # atom | nil, "pin_version_at_creation" => integer | nil}). When absent,
      # an empty ViewVersion is cut — there is no through-line spine to derive
      # segments from.
      argument :segments, {:array, :map}, allow_nil?: true, default: nil

      run fn input, _context ->
        throughline_view_id = input.arguments.throughline_view_id

        throughline_view =
          Storybox.Stories.ThroughlineView
          |> Ash.Query.filter(id == ^throughline_view_id)
          |> Ash.read_one!(authorize?: false)

        story_id = throughline_view.story_id

        segments = Map.get(input.arguments, :segments) || []

        existing_versions =
          Storybox.Stories.ThroughlineViewVersion
          |> Ash.Query.filter(throughline_view_id == ^throughline_view_id)
          |> Ash.read!(authorize?: false)

        next_version_number =
          existing_versions
          |> Enum.map(& &1.version_number)
          |> Enum.max(fn -> 0 end)
          |> Kernel.+(1)

        {:ok, vv} =
          Storybox.Stories.ThroughlineViewVersion
          |> Ash.Changeset.for_create(:create, %{
            throughline_view_id: throughline_view_id,
            version_number: next_version_number
          })
          |> Ash.create(authorize?: false)

        segments
        |> Enum.with_index(1)
        |> Enum.each(fn {segment, position} ->
          base = %{
            view_version_id: vv.id,
            view_version_type: :throughline_vv,
            position: position
          }

          attrs =
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

          Storybox.Stories.Segment
          |> Ash.Changeset.for_create(:create, attrs)
          |> Ash.create!(authorize?: false)
        end)

        Storybox.Stories.TaskGeneration.after_cut(
          vv.id,
          :throughline_vv,
          throughline_view_id,
          :story,
          story_id,
          story_id
        )

        {:ok, vv}
      end
    end
  end
end
