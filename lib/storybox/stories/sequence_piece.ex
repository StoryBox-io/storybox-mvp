defmodule Storybox.Stories.SequencePiece do
  use Ash.Resource,
    domain: Storybox.Stories,
    data_layer: AshPostgres.DataLayer

  require Ash.Query

  postgres do
    table "sequence_pieces"
    repo Storybox.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :content_uri, :string, allow_nil?: false, public?: true
    attribute :version_number, :integer, allow_nil?: false, public?: true
    attribute :weights, :map, default: %{}, public?: true

    attribute :source_synopsis_piece_id, :uuid, allow_nil?: true, public?: true
    attribute :source_version_at_creation, :integer, allow_nil?: true, public?: true

    create_timestamp :inserted_at
  end

  relationships do
    belongs_to :story, Storybox.Stories.Story, allow_nil?: false, public?: true
    belongs_to :sequence, Storybox.Stories.Sequence, allow_nil?: false, public?: true
  end

  actions do
    defaults [:read]

    create :create do
      accept [
        :story_id,
        :sequence_id,
        :content_uri,
        :version_number,
        :weights,
        :source_synopsis_piece_id,
        :source_version_at_creation
      ]
    end

    action :create_version, :struct do
      constraints instance_of: Storybox.Stories.SequencePiece
      argument :story_id, :uuid, allow_nil?: false
      argument :sequence_id, :uuid, allow_nil?: false
      argument :content, :string, allow_nil?: false
      argument :source_synopsis_piece_id, :uuid, allow_nil?: true
      argument :source_version_at_creation, :integer, allow_nil?: true

      run fn input, _context ->
        story_id = input.arguments.story_id
        sequence_id = input.arguments.sequence_id

        existing =
          Storybox.Stories.SequencePiece
          |> Ash.Query.filter(sequence_id == ^sequence_id)
          |> Ash.read!(authorize?: false)

        next_version =
          existing
          |> Enum.map(& &1.version_number)
          |> Enum.max(fn -> 0 end)
          |> Kernel.+(1)

        uri = Storybox.Storage.uri_for_sequence_piece(story_id, sequence_id, next_version)

        with {:ok, _} <- Storybox.Storage.put_content(uri, input.arguments.content),
             {:ok, piece} <-
               Storybox.Stories.SequencePiece
               |> Ash.Changeset.for_create(:create, %{
                 story_id: story_id,
                 sequence_id: sequence_id,
                 content_uri: uri,
                 version_number: next_version,
                 source_synopsis_piece_id: input.arguments[:source_synopsis_piece_id],
                 source_version_at_creation: input.arguments[:source_version_at_creation]
               })
               |> Ash.create(authorize?: false) do
          Storybox.Stories.TaskGeneration.after_piece_version(piece, :sequence_piece)
          {:ok, piece}
        end
      end
    end

    update :set_weights do
      accept [:weights]
    end
  end
end
