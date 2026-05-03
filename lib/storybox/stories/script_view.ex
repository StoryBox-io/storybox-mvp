defmodule Storybox.Stories.ScriptView do
  use Ash.Resource,
    domain: Storybox.Stories,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "script_views"
    repo Storybox.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :title, :string, allow_nil?: false, public?: true
    attribute :approved_version_id, :uuid, allow_nil?: true, public?: true

    timestamps()
  end

  relationships do
    belongs_to :scene, Storybox.Stories.Scene, allow_nil?: false, public?: true
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:title, :scene_id]
    end

    update :update do
      accept [:title]
    end

    update :approve_version do
      argument :version_id, :uuid, allow_nil?: false
      change set_attribute(:approved_version_id, arg(:version_id))
    end
  end
end
