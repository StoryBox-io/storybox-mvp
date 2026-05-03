defmodule Storybox.Stories.SequenceView do
  use Ash.Resource,
    domain: Storybox.Stories,
    data_layer: AshPostgres.DataLayer

  require Ash.Query

  postgres do
    table "sequence_views"
    repo Storybox.Repo
  end

  attributes do
    uuid_primary_key :id
    create_timestamp :inserted_at
  end

  relationships do
    belongs_to :story, Storybox.Stories.Story, allow_nil?: false, public?: true
    belongs_to :sequence, Storybox.Stories.Sequence, allow_nil?: false, public?: true
    has_many :sequence_view_versions, Storybox.Stories.SequenceViewVersion, public?: true
  end

  identities do
    identity :unique_per_story_sequence, [:story_id, :sequence_id]
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:story_id, :sequence_id]
    end

    action :ensure_for_sequence, :struct do
      constraints instance_of: Storybox.Stories.SequenceView
      argument :sequence_id, :uuid, allow_nil?: false
      argument :story_id, :uuid, allow_nil?: false

      run fn input, _context ->
        sequence_id = input.arguments.sequence_id
        story_id = input.arguments.story_id

        existing =
          Storybox.Stories.SequenceView
          |> Ash.Query.filter(sequence_id == ^sequence_id)
          |> Ash.read_one(authorize?: false)

        case existing do
          {:ok, nil} ->
            Storybox.Stories.SequenceView
            |> Ash.Changeset.for_create(:create, %{sequence_id: sequence_id, story_id: story_id})
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
