defmodule Storybox.Stories.CharacterViewVersion do
  use Ash.Resource,
    domain: Storybox.Stories,
    data_layer: AshPostgres.DataLayer

  require Ash.Query

  postgres do
    table "character_view_versions"
    repo Storybox.Repo
  end

  attributes do
    uuid_primary_key :id
    attribute :version_number, :integer, allow_nil?: false, public?: true
    create_timestamp :inserted_at
  end

  relationships do
    belongs_to :character_view, Storybox.Stories.CharacterView, allow_nil?: false, public?: true

    has_many :segments, Storybox.Stories.Segment,
      destination_attribute: :view_version_id,
      filter: [view_version_type: :character_vv],
      public?: true
  end

  identities do
    identity :unique_version_per_view, [:character_view_id, :version_number]
  end

  actions do
    defaults [:read]

    create :create do
      accept [:character_view_id, :version_number]
    end

    action :cut, :struct do
      constraints instance_of: Storybox.Stories.CharacterViewVersion
      argument :character_view_id, :uuid, allow_nil?: false

      run fn input, _context ->
        character_view_id = input.arguments.character_view_id

        character_view =
          Storybox.Stories.CharacterView
          |> Ash.Query.filter(id == ^character_view_id)
          |> Ash.read_one!(authorize?: false)

        character_id = character_view.character_id

        character =
          Storybox.Stories.Character
          |> Ash.Query.filter(id == ^character_id)
          |> Ash.read_one!(authorize?: false)

        story_id = character.story_id

        latest_piece =
          Storybox.Stories.CharacterPiece
          |> Ash.Query.filter(character_id == ^character_id)
          |> Ash.Query.sort(version_number: :desc)
          |> Ash.Query.limit(1)
          |> Ash.read!(authorize?: false)
          |> List.first()

        existing_versions =
          Storybox.Stories.CharacterViewVersion
          |> Ash.Query.filter(character_view_id == ^character_view_id)
          |> Ash.read!(authorize?: false)

        next_version_number =
          existing_versions
          |> Enum.map(& &1.version_number)
          |> Enum.max(fn -> 0 end)
          |> Kernel.+(1)

        {:ok, vv} =
          Storybox.Stories.CharacterViewVersion
          |> Ash.Changeset.for_create(:create, %{
            character_view_id: character_view_id,
            version_number: next_version_number
          })
          |> Ash.create(authorize?: false)

        if latest_piece do
          Storybox.Stories.Segment
          |> Ash.Changeset.for_create(:create, %{
            view_version_id: vv.id,
            view_version_type: :character_vv,
            position: 1,
            pin_id: latest_piece.id,
            pin_type: :character_piece,
            pin_version_at_creation: latest_piece.version_number
          })
          |> Ash.create!(authorize?: false)
        end

        Storybox.Stories.TaskGeneration.after_cut(
          vv.id,
          :character_vv,
          character_view_id,
          :character,
          character_id,
          story_id
        )

        {:ok, vv}
      end
    end
  end
end
