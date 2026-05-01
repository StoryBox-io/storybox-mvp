defmodule Storybox.Stories.SynopsisPiece do
  use Ash.Resource,
    domain: Storybox.Stories,
    data_layer: AshPostgres.DataLayer

  require Ash.Query

  postgres do
    table "synopsis_pieces"
    repo Storybox.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :content_uri, :string, allow_nil?: false, public?: true
    attribute :version_number, :integer, allow_nil?: false, public?: true

    create_timestamp :inserted_at
  end

  relationships do
    belongs_to :story, Storybox.Stories.Story, allow_nil?: false, public?: true
    belongs_to :sequence, Storybox.Stories.Sequence, allow_nil?: false, public?: true
  end

  actions do
    defaults [:read]

    create :create do
      accept [:story_id, :sequence_id, :content_uri, :version_number]
    end

    action :create_version, :struct do
      constraints instance_of: Storybox.Stories.SynopsisPiece
      argument :story_id, :uuid, allow_nil?: false
      argument :sequence_id, :uuid, allow_nil?: false
      argument :content, :string, allow_nil?: false

      run fn input, _context ->
        story_id = input.arguments.story_id
        sequence_id = input.arguments.sequence_id

        existing =
          Storybox.Stories.SynopsisPiece
          |> Ash.Query.filter(sequence_id == ^sequence_id)
          |> Ash.read!(authorize?: false)

        next_version =
          existing
          |> Enum.map(& &1.version_number)
          |> Enum.max(fn -> 0 end)
          |> Kernel.+(1)

        uri = Storybox.Storage.uri_for_synopsis_piece(story_id, sequence_id, next_version)

        with {:ok, _} <- Storybox.Storage.put_content(uri, input.arguments.content) do
          Storybox.Stories.SynopsisPiece
          |> Ash.Changeset.for_create(:create, %{
            story_id: story_id,
            sequence_id: sequence_id,
            content_uri: uri,
            version_number: next_version
          })
          |> Ash.create(authorize?: false)
        end
      end
    end
  end
end
