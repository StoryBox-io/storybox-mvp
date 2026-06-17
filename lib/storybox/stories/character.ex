defmodule Storybox.Stories.Character do
  use Ash.Resource,
    domain: Storybox.Stories,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "characters"
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
    has_many :character_pieces, Storybox.Stories.CharacterPiece, public?: true
    has_one :character_view, Storybox.Stories.CharacterView, public?: true
  end

  identities do
    identity :unique_slug_per_story, [:story_id, :slug]
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:name, :slug, :story_id]

      change Storybox.Stories.Changes.GenerateCharacterSlug
    end

    update :update do
      accept [:name]
    end
  end
end
