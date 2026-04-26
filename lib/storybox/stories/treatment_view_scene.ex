defmodule Storybox.Stories.TreatmentViewScene do
  use Ash.Resource,
    domain: Storybox.Stories,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "treatment_view_scenes"
    repo Storybox.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :position, :integer, allow_nil?: false, public?: true

    timestamps()
  end

  relationships do
    belongs_to :treatment_view, Storybox.Stories.TreatmentView, allow_nil?: false, public?: true
    belongs_to :scene, Storybox.Stories.Scene, allow_nil?: false, public?: true
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:position, :treatment_view_id, :scene_id]
    end
  end
end
