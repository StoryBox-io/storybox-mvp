defmodule Storybox.Stories.World do
  use Ash.Resource,
    domain: Storybox.Stories,
    data_layer: AshPostgres.DataLayer,
    notifiers: [Storybox.Stories.Notifiers.PropagateUpstreamChange]

  postgres do
    table "worlds"
    repo Storybox.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :history, :string, allow_nil?: true, public?: true
    attribute :rules, :string, allow_nil?: true, public?: true
    attribute :subtext, :string, allow_nil?: true, public?: true

    timestamps()
  end

  relationships do
    belongs_to :story, Storybox.Stories.Story, allow_nil?: false, public?: true
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:history, :rules, :subtext, :story_id]
    end

    update :update do
      accept [:history, :rules, :subtext]
    end
  end
end
