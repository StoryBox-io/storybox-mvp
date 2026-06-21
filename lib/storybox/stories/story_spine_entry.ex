defmodule Storybox.Stories.StorySpineEntry do
  use Ash.Resource,
    domain: Storybox.Stories,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "story_spine_entries"
    repo Storybox.Repo

    custom_indexes do
      index [:story_spine_id, :sequence_id]
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :position, :integer, allow_nil?: false, public?: true

    create_timestamp :inserted_at
  end

  relationships do
    belongs_to :story_spine, Storybox.Stories.StorySpine, allow_nil?: false, public?: true
    belongs_to :sequence, Storybox.Stories.Sequence, allow_nil?: false, public?: true
  end

  identities do
    identity :unique_sequence_per_spine, [:story_spine_id, :sequence_id]
    identity :unique_position_per_spine, [:story_spine_id, :position]
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:story_spine_id, :sequence_id, :position]
    end

    update :set_position do
      accept [:position]
    end
  end
end
