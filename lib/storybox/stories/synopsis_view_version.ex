defmodule Storybox.Stories.SynopsisViewVersion do
  use Ash.Resource,
    domain: Storybox.Stories,
    data_layer: AshPostgres.DataLayer

  require Ash.Query

  postgres do
    table "synopsis_view_versions"
    repo Storybox.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :version_number, :integer, allow_nil?: false, public?: true

    create_timestamp :inserted_at
  end

  relationships do
    belongs_to :synopsis_view, Storybox.Stories.SynopsisView, allow_nil?: false, public?: true

    has_many :segments, Storybox.Stories.Segment,
      destination_attribute: :view_version_id,
      filter: [view_version_type: :synopsis_vv],
      public?: true
  end

  identities do
    identity :unique_version_per_view, [:synopsis_view_id, :version_number]
  end

  actions do
    defaults [:read]

    create :create do
      accept [:synopsis_view_id, :version_number]
    end

    action :cut, :struct do
      constraints instance_of: Storybox.Stories.SynopsisViewVersion
      argument :synopsis_view_id, :uuid, allow_nil?: false

      run fn input, _context ->
        synopsis_view_id = input.arguments.synopsis_view_id

        [synopsis_view] =
          Storybox.Stories.SynopsisView
          |> Ash.Query.filter(id == ^synopsis_view_id)
          |> Ash.read!(authorize?: false)

        sequences =
          Storybox.Stories.Sequence
          |> Ash.Query.filter(story_id == ^synopsis_view.story_id)
          |> Ash.Query.sort(inserted_at: :asc)
          |> Ash.read!(authorize?: false)

        existing_versions =
          Storybox.Stories.SynopsisViewVersion
          |> Ash.Query.filter(synopsis_view_id == ^synopsis_view_id)
          |> Ash.read!(authorize?: false)

        next_version_number =
          existing_versions
          |> Enum.map(& &1.version_number)
          |> Enum.max(fn -> 0 end)
          |> Kernel.+(1)

        {:ok, vv} =
          Storybox.Stories.SynopsisViewVersion
          |> Ash.Changeset.for_create(:create, %{
            synopsis_view_id: synopsis_view_id,
            version_number: next_version_number
          })
          |> Ash.create(authorize?: false)

        sequences
        |> Enum.with_index(1)
        |> Enum.each(fn {sequence, position} ->
          latest_piece =
            Storybox.Stories.SynopsisPiece
            |> Ash.Query.filter(sequence_id == ^sequence.id)
            |> Ash.Query.sort(version_number: :desc)
            |> Ash.Query.limit(1)
            |> Ash.read!(authorize?: false)
            |> List.first()

          segment_attrs =
            if latest_piece do
              %{
                view_version_id: vv.id,
                view_version_type: :synopsis_vv,
                position: position,
                sequence_id: sequence.id,
                pin_id: latest_piece.id,
                pin_type: :synopsis_piece,
                pin_version_at_creation: latest_piece.version_number
              }
            else
              %{
                view_version_id: vv.id,
                view_version_type: :synopsis_vv,
                position: position,
                sequence_id: sequence.id
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
