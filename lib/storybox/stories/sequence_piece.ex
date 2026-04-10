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

    attribute :title, :string, allow_nil?: false, public?: true
    attribute :act, :string, allow_nil?: true, public?: true
    attribute :position, :integer, allow_nil?: false, public?: true
    attribute :approved_version_id, :uuid, allow_nil?: true, public?: true

    timestamps()
  end

  relationships do
    belongs_to :story, Storybox.Stories.Story, allow_nil?: false, public?: true
    has_many :sequence_versions, Storybox.Stories.SequenceVersion, public?: true
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:title, :act, :position, :story_id]
    end

    update :update do
      accept [:title, :act, :position]
    end

    update :approve_version do
      argument :version_id, :uuid, allow_nil?: false
      change set_attribute(:approved_version_id, arg(:version_id))
    end

    action :create_version, :struct do
      constraints instance_of: Storybox.Stories.SequenceVersion
      argument :content, :string, allow_nil?: false
      argument :sequence_piece_id, :uuid, allow_nil?: false

      run fn input, _context ->
        piece_id = input.arguments.sequence_piece_id

        [piece] =
          Storybox.Stories.SequencePiece
          |> Ash.Query.filter(id == ^piece_id)
          |> Ash.read!(authorize?: false)

        existing_versions =
          Storybox.Stories.SequenceVersion
          |> Ash.Query.filter(sequence_piece_id == ^piece_id)
          |> Ash.read!(authorize?: false)

        next_version_number =
          existing_versions
          |> Enum.map(& &1.version_number)
          |> Enum.max(fn -> 0 end)
          |> Kernel.+(1)

        uri = Storybox.Storage.uri_for_sequence(piece.story_id, piece_id, next_version_number)

        with {:ok, _} <- Storybox.Storage.put_content(uri, input.arguments.content) do
          Storybox.Stories.SequenceVersion
          |> Ash.Changeset.for_create(:create, %{
            sequence_piece_id: piece_id,
            content_uri: uri,
            version_number: next_version_number,
            upstream_status: :current,
            weights: %{}
          })
          |> Ash.create(authorize?: false)
        end
      end
    end
  end
end
