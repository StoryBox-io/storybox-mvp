defmodule Storybox.Stories.ScriptView do
  use Ash.Resource,
    domain: Storybox.Stories,
    data_layer: AshPostgres.DataLayer

  require Ash.Query

  postgres do
    table "script_views"
    repo Storybox.Repo
  end

  attributes do
    uuid_primary_key :id
    create_timestamp :inserted_at
  end

  relationships do
    belongs_to :scene, Storybox.Stories.Scene, allow_nil?: false, public?: true
    has_many :script_view_versions, Storybox.Stories.ScriptViewVersion, public?: true
  end

  identities do
    identity :unique_scene, [:scene_id]
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:scene_id]
    end

    action :ensure_for_scene, :struct do
      constraints instance_of: Storybox.Stories.ScriptView
      argument :scene_id, :uuid, allow_nil?: false

      run fn input, _context ->
        scene_id = input.arguments.scene_id

        existing =
          Storybox.Stories.ScriptView
          |> Ash.Query.filter(scene_id == ^scene_id)
          |> Ash.read_one(authorize?: false)

        case existing do
          {:ok, nil} ->
            Storybox.Stories.ScriptView
            |> Ash.Changeset.for_create(:create, %{scene_id: scene_id})
            |> Ash.create(authorize?: false)

          {:ok, record} ->
            {:ok, record}

          {:error, error} ->
            {:error, error}
        end
      end
    end
  end
end
