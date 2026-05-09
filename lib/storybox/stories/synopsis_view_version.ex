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
    defaults [:read, :destroy]

    create :create do
      accept [:synopsis_view_id, :version_number]
    end

    action :cut, :struct do
      constraints instance_of: Storybox.Stories.SynopsisViewVersion
      argument :synopsis_view_id, :uuid, allow_nil?: false

      run fn input, _context ->
        synopsis_view_id = input.arguments.synopsis_view_id

        synopsis_view =
          Storybox.Stories.SynopsisView
          |> Ash.Query.filter(id == ^synopsis_view_id)
          |> Ash.read_one!(authorize?: false)

        story_id = synopsis_view.story_id

        sequence_ids = sequence_ids_for_cut(story_id)

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

        sequence_ids
        |> Enum.with_index(1)
        |> Enum.each(fn {seq_id, position} ->
          latest_piece =
            Storybox.Stories.SynopsisPiece
            |> Ash.Query.filter(sequence_id == ^seq_id)
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
                sequence_id: seq_id,
                pin_id: latest_piece.id,
                pin_type: :synopsis_piece,
                pin_version_at_creation: latest_piece.version_number
              }
            else
              %{
                view_version_id: vv.id,
                view_version_type: :synopsis_vv,
                position: position,
                sequence_id: seq_id
              }
            end

          Storybox.Stories.Segment
          |> Ash.Changeset.for_create(:create, segment_attrs)
          |> Ash.create!(authorize?: false)
        end)

        Storybox.Stories.TaskGeneration.after_cut(
          vv.id,
          :synopsis_vv,
          synopsis_view_id,
          :story,
          story_id,
          story_id
        )

        {:ok, vv}
      end
    end
  end

  # Sequence ordering source: the latest TreatmentViewVersion's Segments (in
  # position order). Falls back to story.sequences ordered by inserted_at when
  # the story has no TV/TVV yet — mirrors TVV.cut's own first-cut fallback.
  defp sequence_ids_for_cut(story_id) do
    treatment_view =
      Storybox.Stories.TreatmentView
      |> Ash.Query.filter(story_id == ^story_id)
      |> Ash.Query.load(:treatment_view_versions)
      |> Ash.read_one!(authorize?: false)

    latest_tvv =
      case treatment_view do
        nil ->
          nil

        tv ->
          tv.treatment_view_versions
          |> Enum.sort_by(& &1.version_number, :desc)
          |> List.first()
      end

    case latest_tvv do
      nil ->
        Storybox.Stories.Sequence
        |> Ash.Query.filter(story_id == ^story_id)
        |> Ash.Query.sort(:inserted_at)
        |> Ash.read!(authorize?: false)
        |> Enum.map(& &1.id)

      tvv ->
        Storybox.Stories.Segment
        |> Ash.Query.filter(view_version_id == ^tvv.id and view_version_type == :treatment_vv)
        |> Ash.Query.sort(:position)
        |> Ash.read!(authorize?: false)
        |> Enum.map(& &1.sequence_id)
    end
  end
end
