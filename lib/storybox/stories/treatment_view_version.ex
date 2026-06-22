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

      # Optional explicit segment list. When supplied, these exact, order-free
      # segments are written (each map: %{"sequence_id" => uuid, "pin_id" =>
      # uuid | nil, "pin_type" => string | nil, "pin_version_at_creation" =>
      # integer | nil}). When absent, segments are derived from the live
      # StorySpine order, pinning each Sequence's latest SequencePiece.
      argument :segments, {:array, :map}, allow_nil?: true, default: nil

      run fn input, _context ->
        treatment_view_id = input.arguments.treatment_view_id

        treatment_view =
          Storybox.Stories.TreatmentView
          |> Ash.Query.filter(id == ^treatment_view_id)
          |> Ash.Query.load(:treatment_view_versions)
          |> Ash.read_one!(authorize?: false)

        story_id = treatment_view.story_id

        segments =
          Map.get(input.arguments, :segments) || derive_segments_from_spine(story_id)

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

        segments
        |> Enum.with_index(1)
        |> Enum.each(fn {segment, position} ->
          base = %{
            view_version_id: vv.id,
            view_version_type: :treatment_vv,
            position: position,
            sequence_id: Map.get(segment, "sequence_id")
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
          :treatment_vv,
          treatment_view_id,
          :story,
          story_id,
          story_id
        )

        {:ok, vv}
      end
    end
  end

  # Derives order-free segments from the live StorySpine: one per spine entry in
  # position order, pinning that Sequence's latest SequencePiece (a nil-pin
  # segment when the Sequence has no piece yet). An empty spine yields no
  # segments.
  defp derive_segments_from_spine(story_id) do
    story_id
    |> Storybox.Stories.StorySpine.sequence_ids_in_order()
    |> Enum.map(fn seq_id ->
      latest_piece =
        Storybox.Stories.SequencePiece
        |> Ash.Query.filter(sequence_id == ^seq_id)
        |> Ash.read!(authorize?: false)
        |> Enum.max_by(& &1.version_number, fn -> nil end)

      if latest_piece do
        %{
          "sequence_id" => seq_id,
          "pin_id" => latest_piece.id,
          "pin_type" => :sequence_piece,
          "pin_version_at_creation" => latest_piece.version_number
        }
      else
        %{"sequence_id" => seq_id}
      end
    end)
  end
end
