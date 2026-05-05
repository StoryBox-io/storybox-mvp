defmodule Storybox.Stories.WorldView do
  use Ash.Resource,
    domain: Storybox.Stories,
    data_layer: AshPostgres.DataLayer

  require Ash.Query

  postgres do
    table "world_views"
    repo Storybox.Repo
  end

  attributes do
    uuid_primary_key :id
    create_timestamp :inserted_at
  end

  relationships do
    belongs_to :world, Storybox.Stories.World, allow_nil?: false, public?: true
    has_many :world_view_versions, Storybox.Stories.WorldViewVersion, public?: true
  end

  identities do
    identity :unique_world, [:world_id]
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:world_id]
    end

    action :ensure_for_world, :struct do
      constraints instance_of: Storybox.Stories.WorldView
      argument :world_id, :uuid, allow_nil?: false

      run fn input, _context ->
        world_id = input.arguments.world_id

        existing =
          Storybox.Stories.WorldView
          |> Ash.Query.filter(world_id == ^world_id)
          |> Ash.read_one(authorize?: false)

        case existing do
          {:ok, nil} ->
            Storybox.Stories.WorldView
            |> Ash.Changeset.for_create(:create, %{world_id: world_id})
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
