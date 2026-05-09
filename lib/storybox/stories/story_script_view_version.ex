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

    attribute :source_treatment_view_version_id, :uuid, allow_nil?: false, public?: true

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
      accept [:story_script_view_id, :version_number, :source_treatment_view_version_id]
    end

    action :cut, :struct do
      constraints instance_of: Storybox.Stories.StoryScriptViewVersion
      argument :story_script_view_id, :uuid, allow_nil?: false

      run fn input, _context ->
        story_script_view_id = input.arguments.story_script_view_id

        story_script_view =
          Storybox.Stories.StoryScriptView
          |> Ash.Query.filter(id == ^story_script_view_id)
          |> Ash.read_one!(authorize?: false)

        story_id = story_script_view.story_id

        treatment_view =
          Storybox.Stories.TreatmentView
          |> Ash.Query.filter(story_id == ^story_id)
          |> Ash.read_one!(authorize?: false)

        all_tvvs =
          Storybox.Stories.TreatmentViewVersion
          |> Ash.Query.filter(treatment_view_id == ^treatment_view.id)
          |> Ash.read!(authorize?: false)

        latest_tvv =
          all_tvvs
          |> Enum.max_by(& &1.version_number, fn -> nil end)

        if is_nil(latest_tvv) do
          raise "Story has no TreatmentViewVersion — bootstrap should have created one"
        end

        sequence_ids =
          Storybox.Stories.Segment
          |> Ash.Query.filter(
            view_version_id == ^latest_tvv.id and view_version_type == :treatment_vv
          )
          |> Ash.Query.sort(:position)
          |> Ash.read!(authorize?: false)
          |> Enum.map(& &1.sequence_id)

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
            version_number: next_version_number,
            source_treatment_view_version_id: latest_tvv.id
          })
          |> Ash.create!(authorize?: false)

        sequence_ids
        |> Enum.with_index(1)
        |> Enum.each(fn {seq_id, position} ->
          sequence_view =
            Storybox.Stories.SequenceView
            |> Ash.Query.filter(sequence_id == ^seq_id and story_id == ^story_id)
            |> Ash.read_one(authorize?: false)

          latest_svv =
            case sequence_view do
              {:ok, nil} ->
                nil

              {:ok, sv} ->
                Storybox.Stories.SequenceViewVersion
                |> Ash.Query.filter(sequence_view_id == ^sv.id)
                |> Ash.read!(authorize?: false)
                |> Enum.max_by(& &1.version_number, fn -> nil end)

              {:error, _} ->
                nil
            end

          segment_attrs =
            if latest_svv do
              %{
                view_version_id: vv.id,
                view_version_type: :story_script_vv,
                position: position,
                pin_id: latest_svv.id,
                pin_type: :sequence_vv,
                pin_version_at_creation: latest_svv.version_number
              }
            else
              %{
                view_version_id: vv.id,
                view_version_type: :story_script_vv,
                position: position
              }
            end

          Storybox.Stories.Segment
          |> Ash.Changeset.for_create(:create, segment_attrs)
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
end
