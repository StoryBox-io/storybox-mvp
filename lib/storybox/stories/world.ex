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

    timestamps()
  end

  relationships do
    belongs_to :story, Storybox.Stories.Story, allow_nil?: false, public?: true
    has_many :world_pieces, Storybox.Stories.WorldPiece, public?: true
    has_one :world_view, Storybox.Stories.WorldView, public?: true
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:story_id]
    end

    update :update do
      accept []
    end
  end
end
