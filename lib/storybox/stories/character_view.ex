defmodule Storybox.Stories.CharacterView do
  use Ash.Resource,
    domain: Storybox.Stories,
    data_layer: AshPostgres.DataLayer

  require Ash.Query

  postgres do
    table "character_views"
    repo Storybox.Repo
  end

  attributes do
    uuid_primary_key :id
    create_timestamp :inserted_at
  end

  relationships do
    belongs_to :character, Storybox.Stories.Character, allow_nil?: false, public?: true
    has_many :character_view_versions, Storybox.Stories.CharacterViewVersion, public?: true
  end

  identities do
    identity :unique_character, [:character_id]
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:character_id]
    end

    action :ensure_for_character, :struct do
      constraints instance_of: Storybox.Stories.CharacterView
      argument :character_id, :uuid, allow_nil?: false

      run fn input, _context ->
        character_id = input.arguments.character_id

        existing =
          Storybox.Stories.CharacterView
          |> Ash.Query.filter(character_id == ^character_id)
          |> Ash.read_one(authorize?: false)

        case existing do
          {:ok, nil} ->
            Storybox.Stories.CharacterView
            |> Ash.Changeset.for_create(:create, %{character_id: character_id})
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
