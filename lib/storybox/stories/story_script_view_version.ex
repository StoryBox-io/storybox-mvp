defmodule Storybox.Stories.StoryScriptViewVersion do
  use Ash.Resource,
    domain: Storybox.Stories,
    data_layer: AshPostgres.DataLayer

  require Ash.Query

  postgres do
    table "story_script_view_versions"
    repo Storybox.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :version_number, :integer, allow_nil?: false, public?: true

    create_timestamp :inserted_at
  end

  relationships do
    belongs_to :story_script_view, Storybox.Stories.StoryScriptView,
      allow_nil?: false,
      public?: true

    has_many :segments, Storybox.Stories.Segment,
      public?: true,
      destination_attribute: :view_version_id,
      filter: [view_version_type: :story_script_vv]
  end

  identities do
    identity :unique_version_per_view, [:story_script_view_id, :version_number]
  end

  actions do
    defaults [:read]

    create :create do
      accept [:story_script_view_id, :version_number]
    end

    action :cut, :struct do
      constraints instance_of: Storybox.Stories.StoryScriptViewVersion
      argument :story_script_view_id, :uuid, allow_nil?: false

      # Optional explicit segment list. When supplied, these exact, order-free
      # segments are written (each map: %{"sequence_id" => uuid, "pin_id" =>
      # uuid | nil, "pin_type" => string | nil, "pin_version_at_creation" =>
      # integer | nil}). When absent, segments are derived from the live
      # StorySpine order, pinning each Sequence's latest SequenceViewVersion.
      argument :segments, {:array, :map}, allow_nil?: true, default: nil

      run fn input, _context ->
        story_script_view_id = input.arguments.story_script_view_id

        story_script_view =
          Storybox.Stories.StoryScriptView
          |> Ash.Query.filter(id == ^story_script_view_id)
          |> Ash.read_one!(authorize?: false)

        story_id = story_script_view.story_id

        segments =
          Map.get(input.arguments, :segments) || derive_segments_from_spine(story_id)

        existing_versions =
          Storybox.Stories.StoryScriptViewVersion
          |> Ash.Query.filter(story_script_view_id == ^story_script_view_id)
          |> Ash.read!(authorize?: false)

        next_version_number =
          existing_versions
          |> Enum.map(& &1.version_number)
          |> Enum.max(fn -> 0 end)
          |> Kernel.+(1)

        vv =
          Storybox.Stories.StoryScriptViewVersion
          |> Ash.Changeset.for_create(:create, %{
            story_script_view_id: story_script_view_id,
            version_number: next_version_number
          })
          |> Ash.create!(authorize?: false)

        segments
        |> Enum.with_index(1)
        |> Enum.each(fn {segment, position} ->
          base = %{
            view_version_id: vv.id,
            view_version_type: :story_script_vv,
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
          :story_script_vv,
          story_script_view_id,
          :story,
          story_id,
          story_id
        )

        {:ok, vv}
      end
    end
  end

  # Derives order-free segments from the live StorySpine: one per spine entry in
  # position order (keyed by `sequence_id`), pinning that Sequence's latest
  # SequenceViewVersion (a nil-pin segment when the Sequence has no SequenceView
  # /VV yet). An empty spine yields no segments.
  defp derive_segments_from_spine(story_id) do
    story_id
    |> Storybox.Stories.StorySpine.sequence_ids_in_order()
    |> Enum.map(fn seq_id ->
      latest_svv = latest_sequence_view_version(seq_id, story_id)

      if latest_svv do
        %{
          "sequence_id" => seq_id,
          "pin_id" => latest_svv.id,
          "pin_type" => :sequence_vv,
          "pin_version_at_creation" => latest_svv.version_number
        }
      else
        %{"sequence_id" => seq_id}
      end
    end)
  end

  defp latest_sequence_view_version(sequence_id, story_id) do
    sequence_view =
      Storybox.Stories.SequenceView
      |> Ash.Query.filter(sequence_id == ^sequence_id and story_id == ^story_id)
      |> Ash.read_one!(authorize?: false)

    case sequence_view do
      nil ->
        nil

      sv ->
        Storybox.Stories.SequenceViewVersion
        |> Ash.Query.filter(sequence_view_id == ^sv.id)
        |> Ash.read!(authorize?: false)
        |> Enum.max_by(& &1.version_number, fn -> nil end)
    end
  end
end
