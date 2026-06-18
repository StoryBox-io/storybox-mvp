defmodule Storybox.Stories.World do
  use Ash.Resource,
    domain: Storybox.Stories,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "worlds"
    repo Storybox.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string, allow_nil?: false, public?: true
    attribute :slug, :string, allow_nil?: false, public?: true

    timestamps()
  end

  relationships do
    belongs_to :story, Storybox.Stories.Story, allow_nil?: false, public?: true
    has_many :world_pieces, Storybox.Stories.WorldPiece, public?: true
    has_one :world_view, Storybox.Stories.WorldView, public?: true
  end

  identities do
    identity :unique_slug_per_story, [:story_id, :slug]
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:name, :slug, :story_id]

      change Storybox.Stories.Changes.GenerateWorldSlug
    end

    update :update do
      accept [:name]
    end
  end
end
