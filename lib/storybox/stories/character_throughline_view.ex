defmodule Storybox.Stories.CharacterThroughlineView do
  use Ash.Resource,
    domain: Storybox.Stories,
    data_layer: AshPostgres.DataLayer

  require Ash.Query

  postgres do
    table "character_throughline_views"
    repo Storybox.Repo
  end

  attributes do
    uuid_primary_key :id

    create_timestamp :inserted_at
  end

  relationships do
    # The Character reference sits here, on the per-character view, rather than
    # on the ThroughlinePiece it pins — the piece stays inert.
    belongs_to :story, Storybox.Stories.Story, allow_nil?: false, public?: true
    belongs_to :character, Storybox.Stories.Character, allow_nil?: false, public?: true

    has_many :character_throughline_view_versions,
             Storybox.Stories.CharacterThroughlineViewVersion,
             public?: true
  end

  identities do
    identity :unique_story_character, [:story_id, :character_id]
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:story_id, :character_id]
    end

    action :ensure_for_story_character, :struct do
      constraints instance_of: Storybox.Stories.CharacterThroughlineView
      argument :story_id, :uuid, allow_nil?: false
      argument :character_id, :uuid, allow_nil?: false

      run fn input, _context ->
        story_id = input.arguments.story_id
        character_id = input.arguments.character_id

        case Storybox.Stories.CharacterThroughlineView
             |> Ash.Query.filter(story_id == ^story_id and character_id == ^character_id)
             |> Ash.read_one!(authorize?: false) do
          nil ->
            Storybox.Stories.CharacterThroughlineView
            |> Ash.Changeset.for_create(:create, %{
              story_id: story_id,
              character_id: character_id
            })
            |> Ash.create(authorize?: false)

          existing ->
            {:ok, existing}
        end
      end
    end
  end
end
