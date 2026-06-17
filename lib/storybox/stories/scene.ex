defmodule Storybox.Stories.Scene do
  use Ash.Resource,
    domain: Storybox.Stories,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "scenes"
    repo Storybox.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :motif, :string, allow_nil?: true, public?: true
    attribute :slug, :string, allow_nil?: false, public?: true

    timestamps()
  end

  relationships do
    belongs_to :story, Storybox.Stories.Story, allow_nil?: false, public?: true
    has_one :script_view, Storybox.Stories.ScriptView, public?: true
    has_many :script_pieces, Storybox.Stories.ScriptPiece, public?: true
  end

  identities do
    identity :unique_slug_per_story, [:story_id, :slug]
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:motif, :slug, :story_id]

      change Storybox.Stories.Changes.GenerateSceneSlug
      change Storybox.Stories.Changes.WarnCharacterSlugCollision
    end

    update :update do
      accept [:motif, :slug]

      # The collision warning runs as an after_action hook, which cannot be
      # expressed atomically; the warning is non-fatal so this is safe.
      require_atomic? false

      change Storybox.Stories.Changes.WarnCharacterSlugCollision
    end
  end
end
