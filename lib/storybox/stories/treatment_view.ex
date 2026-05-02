defmodule Storybox.Stories.TreatmentView do
  use Ash.Resource,
    domain: Storybox.Stories,
    data_layer: AshPostgres.DataLayer

  require Ash.Query

  postgres do
    table "treatment_views"
    repo Storybox.Repo
  end

  attributes do
    uuid_primary_key :id
    create_timestamp :inserted_at
  end

  relationships do
    belongs_to :story, Storybox.Stories.Story, allow_nil?: false, public?: true

    has_many :treatment_view_versions, Storybox.Stories.TreatmentViewVersion, public?: true
  end

  identities do
    identity :unique_story, [:story_id]
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:story_id]
    end

    action :ensure_for_story, :struct do
      constraints instance_of: Storybox.Stories.TreatmentView
      argument :story_id, :uuid, allow_nil?: false

      run fn input, _context ->
        story_id = input.arguments.story_id

        existing =
          Storybox.Stories.TreatmentView
          |> Ash.Query.filter(story_id == ^story_id)
          |> Ash.read_one(authorize?: false)

        case existing do
          {:ok, nil} ->
            Storybox.Stories.TreatmentView
            |> Ash.Changeset.for_create(:create, %{story_id: story_id})
            |> Ash.create(authorize?: false)

          {:ok, record} ->
            {:ok, record}

          {:error, error} ->
            {:error, error}
        end
      end
    end
  end
end
