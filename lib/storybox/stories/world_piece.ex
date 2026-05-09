defmodule Storybox.Stories.WorldPiece do
  use Ash.Resource,
    domain: Storybox.Stories,
    data_layer: AshPostgres.DataLayer

  require Ash.Query

  postgres do
    table "world_pieces"
    repo Storybox.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :content_uri, :string, allow_nil?: false, public?: true
    attribute :version_number, :integer, allow_nil?: false, public?: true

    create_timestamp :inserted_at
  end

  relationships do
    belongs_to :world, Storybox.Stories.World, allow_nil?: false, public?: true
  end

  identities do
    identity :unique_version_per_world, [:world_id, :version_number]
  end

  actions do
    defaults [:read]

    create :create do
      accept [:world_id, :content_uri, :version_number]
    end

    action :create_version, :struct do
      constraints instance_of: Storybox.Stories.WorldPiece
      argument :world_id, :uuid, allow_nil?: false
      argument :content, :string, allow_nil?: false

      run fn input, _context ->
        world_id = input.arguments.world_id

        existing =
          Storybox.Stories.WorldPiece
          |> Ash.Query.filter(world_id == ^world_id)
          |> Ash.read!(authorize?: false)

        next_version =
          existing
          |> Enum.map(& &1.version_number)
          |> Enum.max(fn -> 0 end)
          |> Kernel.+(1)

        uri = Storybox.Storage.uri_for_world_piece(world_id, next_version)

        with {:ok, _} <- Storybox.Storage.put_content(uri, input.arguments.content),
             {:ok, piece} <-
               Storybox.Stories.WorldPiece
               |> Ash.Changeset.for_create(:create, %{
                 world_id: world_id,
                 content_uri: uri,
                 version_number: next_version
               })
               |> Ash.create(authorize?: false) do
          Storybox.Stories.TaskGeneration.after_piece_version(piece, :world_piece)
          {:ok, piece}
        end
      end
    end
  end
end
