defmodule Storybox.Stories.SequenceViewVersion do
  use Ash.Resource,
    domain: Storybox.Stories,
    data_layer: AshPostgres.DataLayer

  require Ash.Query

  postgres do
    table "sequence_view_versions"
    repo Storybox.Repo
  end

  attributes do
    uuid_primary_key :id
    attribute :version_number, :integer, allow_nil?: false, public?: true
    create_timestamp :inserted_at
  end

  relationships do
    belongs_to :sequence_view, Storybox.Stories.SequenceView, allow_nil?: false, public?: true

    has_many :segments, Storybox.Stories.Segment,
      destination_attribute: :view_version_id,
      filter: [view_version_type: :sequence_vv],
      public?: true
  end

  identities do
    identity :unique_version_per_view, [:sequence_view_id, :version_number]
  end

  actions do
    defaults [:read]

    create :create do
      accept [:sequence_view_id, :version_number]
    end

    action :cut, :struct do
      constraints instance_of: Storybox.Stories.SequenceViewVersion
      argument :sequence_view_id, :uuid, allow_nil?: false

      # Explicit, order-bearing scene segments for this Sequence's inner cut.
      # Each map carries the scene plus an optional pin:
      #   %{"scene_id" => uuid,
      #     "pin_id" => uuid | nil,
      #     "pin_type" => "script_vv" | nil,
      #     "pin_version_at_creation" => integer | nil}
      # A map with no pin keys (or a nil pin_id) produces a deliberate nil-pin
      # Segment. Inner scene order is the list order (Segment.position 1..N).
      argument :segments, {:array, :map}, allow_nil?: false

      run fn input, _context ->
        sequence_view_id = input.arguments.sequence_view_id
        segments = input.arguments.segments

        sequence_view =
          Storybox.Stories.SequenceView
          |> Ash.Query.filter(id == ^sequence_view_id)
          |> Ash.read_one!(authorize?: false)

        story_id = sequence_view.story_id

        existing_versions =
          Storybox.Stories.SequenceViewVersion
          |> Ash.Query.filter(sequence_view_id == ^sequence_view_id)
          |> Ash.read!(authorize?: false)

        next_version_number =
          existing_versions
          |> Enum.map(& &1.version_number)
          |> Enum.max(fn -> 0 end)
          |> Kernel.+(1)

        {:ok, vv} =
          Storybox.Stories.SequenceViewVersion
          |> Ash.Changeset.for_create(:create, %{
            sequence_view_id: sequence_view_id,
            version_number: next_version_number
          })
          |> Ash.create(authorize?: false)

        segments
        |> Enum.with_index(1)
        |> Enum.each(fn {segment, position} ->
          base = %{
            view_version_id: vv.id,
            view_version_type: :sequence_vv,
            position: position,
            scene_id: Map.get(segment, "scene_id")
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
          :sequence_vv,
          sequence_view_id,
          :story,
          story_id,
          story_id
        )

        {:ok, vv}
      end
    end
  end
end
