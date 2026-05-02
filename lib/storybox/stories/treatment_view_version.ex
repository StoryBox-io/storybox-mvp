defmodule Storybox.Stories.TreatmentViewVersion do
  use Ash.Resource,
    domain: Storybox.Stories,
    data_layer: AshPostgres.DataLayer

  require Ash.Query

  postgres do
    table "treatment_view_versions"
    repo Storybox.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :version_number, :integer, allow_nil?: false, public?: true

    create_timestamp :inserted_at
  end

  relationships do
    belongs_to :treatment_view, Storybox.Stories.TreatmentView, allow_nil?: false, public?: true

    has_many :segments, Storybox.Stories.Segment,
      public?: true,
      destination_attribute: :view_version_id,
      filter: [view_version_type: :treatment_vv]
  end

  identities do
    identity :unique_version_per_view, [:treatment_view_id, :version_number]
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:treatment_view_id, :version_number]
    end

    action :cut, :struct do
      constraints instance_of: Storybox.Stories.TreatmentViewVersion
      argument :treatment_view_id, :uuid, allow_nil?: false

      run fn input, _context ->
        treatment_view_id = input.arguments.treatment_view_id

        treatment_view =
          Storybox.Stories.TreatmentView
          |> Ash.Query.filter(id == ^treatment_view_id)
          |> Ash.Query.load(:treatment_view_versions)
          |> Ash.read_one!(authorize?: false)

        story_id = treatment_view.story_id

        prior_vv =
          treatment_view.treatment_view_versions
          |> Enum.sort_by(& &1.version_number, :desc)
          |> List.first()

        sequence_ids =
          if prior_vv do
            Storybox.Stories.Segment
            |> Ash.Query.filter(
              view_version_id == ^prior_vv.id and view_version_type == :treatment_vv
            )
            |> Ash.Query.sort(:position)
            |> Ash.read!(authorize?: false)
            |> Enum.map(& &1.sequence_id)
          else
            Storybox.Stories.Sequence
            |> Ash.Query.filter(story_id == ^story_id)
            |> Ash.Query.sort(:inserted_at)
            |> Ash.read!(authorize?: false)
            |> Enum.map(& &1.id)
          end

        next_version =
          treatment_view.treatment_view_versions
          |> Enum.map(& &1.version_number)
          |> Enum.max(fn -> 0 end)
          |> Kernel.+(1)

        vv =
          Storybox.Stories.TreatmentViewVersion
          |> Ash.Changeset.for_create(:create, %{
            treatment_view_id: treatment_view_id,
            version_number: next_version
          })
          |> Ash.create!(authorize?: false)

        sequence_ids
        |> Enum.with_index(1)
        |> Enum.each(fn {seq_id, position} ->
          latest_piece =
            Storybox.Stories.SequencePiece
            |> Ash.Query.filter(sequence_id == ^seq_id)
            |> Ash.read!(authorize?: false)
            |> Enum.max_by(& &1.version_number, fn -> nil end)

          segment_attrs =
            if latest_piece do
              %{
                view_version_id: vv.id,
                view_version_type: :treatment_vv,
                position: position,
                sequence_id: seq_id,
                pin_id: latest_piece.id,
                pin_type: :sequence_piece,
                pin_version_at_creation: latest_piece.version_number
              }
            else
              %{
                view_version_id: vv.id,
                view_version_type: :treatment_vv,
                position: position,
                sequence_id: seq_id
              }
            end

          Storybox.Stories.Segment
          |> Ash.Changeset.for_create(:create, segment_attrs)
          |> Ash.create!(authorize?: false)
        end)

        {:ok, vv}
      end
    end
  end
end
