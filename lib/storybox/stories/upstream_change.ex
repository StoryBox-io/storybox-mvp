defmodule Storybox.Stories.UpstreamChange do
  use Ash.Resource,
    domain: Storybox.Stories,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "upstream_changes"
    repo Storybox.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :piece_version_type, :atom,
      constraints: [one_of: [:sequence_version, :scene_version]],
      allow_nil?: false,
      public?: true

    attribute :piece_version_id, :uuid, allow_nil?: false, public?: true

    attribute :component_type, :atom,
      constraints: [one_of: [:story, :character, :world]],
      allow_nil?: false,
      public?: true

    attribute :component_id, :uuid, allow_nil?: false, public?: true

    attribute :version_before, :string, allow_nil?: true, public?: true
    attribute :version_after, :string, allow_nil?: true, public?: true

    attribute :acknowledged, :boolean, default: false, allow_nil?: false, public?: true

    create_timestamp :inserted_at
  end

  actions do
    defaults [:read]

    create :create do
      accept [
        :piece_version_type,
        :piece_version_id,
        :component_type,
        :component_id,
        :version_before,
        :version_after
      ]
    end

    update :acknowledge do
      accept []

      change set_attribute(:acknowledged, true)
    end
  end
end
