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
      argument :script_view_version_ids, {:array, :uuid}, allow_nil?: false

      run fn input, _context ->
        sequence_view_id = input.arguments.sequence_view_id
        script_view_version_ids = input.arguments.script_view_version_ids

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

        script_view_version_ids
        |> Enum.with_index(1)
        |> Enum.each(fn {svv_id, position} ->
          svv =
            Storybox.Stories.ScriptViewVersion
            |> Ash.Query.filter(id == ^svv_id)
            |> Ash.read_one!(authorize?: false)

          Storybox.Stories.Segment
          |> Ash.Changeset.for_create(:create, %{
            view_version_id: vv.id,
            view_version_type: :sequence_vv,
            position: position,
            pin_id: svv.id,
            pin_type: :script_vv,
            pin_version_at_creation: svv.version_number
          })
          |> Ash.create!(authorize?: false)
        end)

        {:ok, vv}
      end
    end
  end
end
