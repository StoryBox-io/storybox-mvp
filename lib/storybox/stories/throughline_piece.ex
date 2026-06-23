defmodule Storybox.Stories.ThroughlinePiece do
  use Ash.Resource,
    domain: Storybox.Stories,
    data_layer: AshPostgres.DataLayer

  require Ash.Query

  postgres do
    table "throughline_pieces"
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
    belongs_to :story, Storybox.Stories.Story, allow_nil?: false, public?: true

    # nil character = the Story's controlling idea; a set character = that
    # character's through-line (arc-in-this-story). (story_id, character_id) is
    # the version lineage key.
    belongs_to :character, Storybox.Stories.Character, allow_nil?: true, public?: true
  end

  actions do
    defaults [:read]

    create :create do
      accept [
        :story_id,
        :character_id,
        :content_uri,
        :version_number,
        :weights
      ]
    end

    action :create_version, :struct do
      constraints instance_of: Storybox.Stories.ThroughlinePiece
      argument :story_id, :uuid, allow_nil?: false
      argument :character_id, :uuid, allow_nil?: true, default: nil
      argument :content, :string, allow_nil?: false

      run fn input, _context ->
        story_id = input.arguments.story_id
        character_id = Map.get(input.arguments, :character_id)

        existing =
          story_id
          |> lineage_query(character_id)
          |> Ash.read!(authorize?: false)

        next_version =
          existing
          |> Enum.map(& &1.version_number)
          |> Enum.max(fn -> 0 end)
          |> Kernel.+(1)

        uri = Storybox.Storage.uri_for_throughline_piece(story_id, character_id, next_version)

        with {:ok, _} <- Storybox.Storage.put_content(uri, input.arguments.content),
             {:ok, piece} <-
               Storybox.Stories.ThroughlinePiece
               |> Ash.Changeset.for_create(:create, %{
                 story_id: story_id,
                 character_id: character_id,
                 content_uri: uri,
                 version_number: next_version
               })
               |> Ash.create(authorize?: false) do
          Storybox.Stories.TaskGeneration.after_piece_version(piece, :throughline_piece)
          {:ok, piece}
        end
      end
    end
  end

  # Builds the lineage query for a (story_id, character_id) pair. A nil
  # character_id (the controlling idea) must be matched with is_nil/1, not an
  # equality check.
  defp lineage_query(story_id, nil) do
    Storybox.Stories.ThroughlinePiece
    |> Ash.Query.filter(story_id == ^story_id and is_nil(character_id))
  end

  defp lineage_query(story_id, character_id) do
    Storybox.Stories.ThroughlinePiece
    |> Ash.Query.filter(story_id == ^story_id and character_id == ^character_id)
  end
end
