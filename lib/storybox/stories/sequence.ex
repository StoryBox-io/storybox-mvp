defmodule Storybox.Stories.Sequence do
  use Ash.Resource,
    domain: Storybox.Stories,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "sequences"
    repo Storybox.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string, allow_nil?: false, public?: true
    attribute :slug, :string, allow_nil?: false, public?: true

    create_timestamp :inserted_at
  end

  relationships do
    belongs_to :story, Storybox.Stories.Story, allow_nil?: false, public?: true
  end

  identities do
    identity :unique_slug_per_story, [:story_id, :slug]
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:story_id, :name, :slug]
    end

    update :update do
      accept [:name]
    end
  end
end
