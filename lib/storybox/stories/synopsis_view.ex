defmodule Storybox.Stories.SynopsisView do
  use Ash.Resource,
    domain: Storybox.Stories,
    data_layer: AshPostgres.DataLayer

  require Ash.Query

  postgres do
    table "synopsis_views"
    repo Storybox.Repo
  end

  attributes do
    uuid_primary_key :id

    create_timestamp :inserted_at
  end

  relationships do
    belongs_to :story, Storybox.Stories.Story, allow_nil?: false, public?: true

    has_many :synopsis_view_versions, Storybox.Stories.SynopsisViewVersion, public?: true
  end

  identities do
    identity :unique_story, [:story_id]
  end

  actions do
    defaults [:read]

    create :create do
      accept [:story_id]
    end

    action :ensure_for_story, :struct do
      constraints instance_of: Storybox.Stories.SynopsisView
      argument :story_id, :uuid, allow_nil?: false

      run fn input, _context ->
        story_id = input.arguments.story_id

        case Storybox.Stories.SynopsisView
             |> Ash.Query.filter(story_id == ^story_id)
             |> Ash.read_one!(authorize?: false) do
          nil ->
            Storybox.Stories.SynopsisView
            |> Ash.Changeset.for_create(:create, %{story_id: story_id})
            |> Ash.create(authorize?: false)

          existing ->
            {:ok, existing}
        end
      end
    end
  end
end
