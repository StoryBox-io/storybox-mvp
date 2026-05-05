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

    timestamps()
  end

  relationships do
    belongs_to :story, Storybox.Stories.Story, allow_nil?: false, public?: true
    has_many :character_pieces, Storybox.Stories.CharacterPiece, public?: true
    has_one :character_view, Storybox.Stories.CharacterView, public?: true
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:name, :story_id]
    end

    update :update do
      accept [:name]
    end
  end
end
