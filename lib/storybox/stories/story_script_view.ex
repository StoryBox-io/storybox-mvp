defmodule Storybox.Stories.StoryScriptView do
  use Ash.Resource,
    domain: Storybox.Stories,
    data_layer: AshPostgres.DataLayer

  require Ash.Query

  postgres do
    table "story_script_views"
    repo Storybox.Repo
  end

  attributes do
    uuid_primary_key :id
    create_timestamp :inserted_at
  end

  relationships do
    belongs_to :story, Storybox.Stories.Story, allow_nil?: false, public?: true

    has_many :story_script_view_versions, Storybox.Stories.StoryScriptViewVersion, public?: true
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
      constraints instance_of: Storybox.Stories.StoryScriptView
      argument :story_id, :uuid, allow_nil?: false

      run fn input, _context ->
        story_id = input.arguments.story_id

        existing =
          Storybox.Stories.StoryScriptView
          |> Ash.Query.filter(story_id == ^story_id)
          |> Ash.read_one(authorize?: false)

        case existing do
          {:ok, nil} ->
            Storybox.Stories.StoryScriptView
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
