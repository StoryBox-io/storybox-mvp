defmodule Storybox.Stories.TreatmentPiece do
  use Ash.Resource,
    domain: Storybox.Stories,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "treatment_pieces"
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
    belongs_to :treatment_view, Storybox.Stories.TreatmentView, allow_nil?: false, public?: true
  end

  actions do
    defaults [:read]

    create :create do
      accept [:treatment_view_id, :content_uri, :version_number, :upstream_status, :weights]
    end

    update :mark_stale do
      change set_attribute(:upstream_status, :stale)
    end

    update :set_weights do
      accept [:weights]
    end
  end
end
