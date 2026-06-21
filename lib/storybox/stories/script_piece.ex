defmodule Storybox.Stories.ScriptPiece do
  use Ash.Resource,
    domain: Storybox.Stories,
    data_layer: AshPostgres.DataLayer

  require Ash.Query

  postgres do
    table "script_pieces"
    repo Storybox.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :content_uri, :string, allow_nil?: false, public?: true
    attribute :version_number, :integer, allow_nil?: false, public?: true
    attribute :weights, :map, default: %{}, public?: true

    create_timestamp :inserted_at
  end

  relationships do
    belongs_to :scene, Storybox.Stories.Scene, allow_nil?: false, public?: true
  end

  identities do
    identity :unique_version_per_scene, [:scene_id, :version_number]
  end

  actions do
    defaults [:read]

    create :create do
      accept [
        :scene_id,
        :content_uri,
        :version_number,
        :weights
      ]
    end

    action :create_version, :struct do
      constraints instance_of: Storybox.Stories.ScriptPiece
      argument :scene_id, :uuid, allow_nil?: false
      argument :content, :string, allow_nil?: false

      run fn input, _context ->
        scene_id = input.arguments.scene_id

        existing =
          Storybox.Stories.ScriptPiece
          |> Ash.Query.filter(scene_id == ^scene_id)
          |> Ash.read!(authorize?: false)

        next_version =
          existing
          |> Enum.map(& &1.version_number)
          |> Enum.max(fn -> 0 end)
          |> Kernel.+(1)

        uri = Storybox.Storage.uri_for_script_piece(scene_id, next_version)

        with {:ok, _} <- Storybox.Storage.put_content(uri, input.arguments.content),
             {:ok, piece} <-
               Storybox.Stories.ScriptPiece
               |> Ash.Changeset.for_create(:create, %{
                 scene_id: scene_id,
                 content_uri: uri,
                 version_number: next_version
               })
               |> Ash.create(authorize?: false) do
          Storybox.Stories.TaskGeneration.after_piece_version(piece, :script_piece)
          {:ok, piece}
        end
      end
    end

    update :set_weights do
      accept [:weights]
    end
  end
end
