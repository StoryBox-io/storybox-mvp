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

    attribute :title, :string, allow_nil?: false, public?: true
    attribute :slug, :string, allow_nil?: true, public?: true

    timestamps()
  end

  relationships do
    belongs_to :story, Storybox.Stories.Story, allow_nil?: false, public?: true
    has_one :script_view, Storybox.Stories.ScriptView, public?: true
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:title, :slug, :story_id]
    end

    update :update do
      accept [:title, :slug]
    end
  end
end
