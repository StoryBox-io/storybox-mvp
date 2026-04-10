defmodule Storybox.Stories.Character do
  use Ash.Resource,
    domain: Storybox.Stories,
    data_layer: AshPostgres.DataLayer,
    notifiers: [Storybox.Stories.Notifiers.PropagateUpstreamChange]

  postgres do
    table "characters"
    repo Storybox.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string, allow_nil?: false, public?: true
    attribute :essence, :string, allow_nil?: true, public?: true
    attribute :contradictions, {:array, :string}, allow_nil?: true, public?: true
    attribute :voice, :string, allow_nil?: true, public?: true

    timestamps()
  end

  relationships do
    belongs_to :story, Storybox.Stories.Story, allow_nil?: false, public?: true
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:name, :essence, :contradictions, :voice, :story_id]
    end

    update :update do
      accept [:name, :essence, :contradictions, :voice]
    end
  end
end
