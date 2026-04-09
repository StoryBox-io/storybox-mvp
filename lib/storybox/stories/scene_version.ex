defmodule Storybox.Stories.SceneVersion do
  use Ash.Resource,
    domain: Storybox.Stories,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "scene_versions"
    repo Storybox.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :content_uri, :string, allow_nil?: false, public?: true
    attribute :version_number, :integer, allow_nil?: false, public?: true
    attribute :weights, :map, default: %{}, public?: true

    attribute :upstream_status, :atom,
      constraints: [one_of: [:current, :stale]],
      default: :current,
      allow_nil?: false,
      public?: true

    create_timestamp :inserted_at
  end

  relationships do
    belongs_to :scene_piece, Storybox.Stories.ScenePiece, allow_nil?: false, public?: true
  end

  actions do
    defaults [:read]

    create :create do
      accept [:scene_piece_id, :content_uri, :version_number, :upstream_status, :weights]
    end
  end
end
