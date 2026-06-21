defmodule Storybox.Stories.StorySpine do
  use Ash.Resource,
    domain: Storybox.Stories,
    data_layer: AshPostgres.DataLayer

  require Ash.Query

  postgres do
    table "story_spines"
    repo Storybox.Repo
  end

  attributes do
    uuid_primary_key :id
    create_timestamp :inserted_at
  end

  relationships do
    belongs_to :story, Storybox.Stories.Story, allow_nil?: false, public?: true

    has_many :story_spine_entries, Storybox.Stories.StorySpineEntry, public?: true
    has_many :story_spine_view_versions, Storybox.Stories.StorySpineViewVersion, public?: true
  end

  identities do
    identity :unique_story, [:story_id]
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:story_id]
    end

    action :ensure_for_story, :struct do
      constraints instance_of: Storybox.Stories.StorySpine
      argument :story_id, :uuid, allow_nil?: false

      run fn input, _context ->
        story_id = input.arguments.story_id

        existing =
          Storybox.Stories.StorySpine
          |> Ash.Query.filter(story_id == ^story_id)
          |> Ash.read_one(authorize?: false)

        case existing do
          {:ok, nil} ->
            Storybox.Stories.StorySpine
            |> Ash.Changeset.for_create(:create, %{story_id: story_id})
            |> Ash.create(authorize?: false)

          {:ok, record} ->
            {:ok, record}

          {:error, error} ->
            {:error, error}
        end
      end
    end

    action :add_entry, :struct do
      constraints instance_of: Storybox.Stories.StorySpineEntry
      argument :story_spine_id, :uuid, allow_nil?: false
      argument :sequence_id, :uuid, allow_nil?: false
      argument :position, :integer, allow_nil?: true

      run fn input, _context ->
        story_spine_id = input.arguments.story_spine_id
        sequence_id = input.arguments.sequence_id

        position =
          case Map.get(input.arguments, :position) do
            nil ->
              max_position =
                Storybox.Stories.StorySpineEntry
                |> Ash.Query.filter(story_spine_id == ^story_spine_id)
                |> Ash.read!(authorize?: false)
                |> Enum.map(& &1.position)
                |> Enum.max(fn -> 0 end)

              max_position + 1

            pos ->
              pos
          end

        Storybox.Stories.StorySpineEntry
        |> Ash.Changeset.for_create(:create, %{
          story_spine_id: story_spine_id,
          sequence_id: sequence_id,
          position: position
        })
        |> Ash.create(authorize?: false)
      end
    end

    action :remove_entry, :struct do
      constraints instance_of: Storybox.Stories.StorySpine
      argument :story_spine_id, :uuid, allow_nil?: false
      argument :sequence_id, :uuid, allow_nil?: false

      run fn input, _context ->
        story_spine_id = input.arguments.story_spine_id
        sequence_id = input.arguments.sequence_id

        entries =
          Storybox.Stories.StorySpineEntry
          |> Ash.Query.filter(story_spine_id == ^story_spine_id)
          |> Ash.Query.sort(:position)
          |> Ash.read!(authorize?: false)

        target = Enum.find(entries, &(&1.sequence_id == sequence_id))

        if is_nil(target) do
          {:error, "No spine entry for sequence #{sequence_id} on spine #{story_spine_id}"}
        else
          Ash.destroy!(target, authorize?: false)

          entries
          |> Enum.reject(&(&1.id == target.id))
          |> repack_positions()

          Storybox.Stories.StorySpine
          |> Ash.Query.filter(id == ^story_spine_id)
          |> Ash.read_one(authorize?: false)
        end
      end
    end

    action :reorder_entry, :struct do
      constraints instance_of: Storybox.Stories.StorySpineEntry
      argument :story_spine_id, :uuid, allow_nil?: false
      argument :sequence_id, :uuid, allow_nil?: false
      argument :new_position, :integer, allow_nil?: false

      run fn input, _context ->
        story_spine_id = input.arguments.story_spine_id
        sequence_id = input.arguments.sequence_id
        new_position = input.arguments.new_position

        entries =
          Storybox.Stories.StorySpineEntry
          |> Ash.Query.filter(story_spine_id == ^story_spine_id)
          |> Ash.Query.sort(:position)
          |> Ash.read!(authorize?: false)

        target = Enum.find(entries, &(&1.sequence_id == sequence_id))

        if is_nil(target) do
          {:error, "No spine entry for sequence #{sequence_id} on spine #{story_spine_id}"}
        else
          count = length(entries)
          clamped = new_position |> max(1) |> min(count)

          reordered =
            entries
            |> Enum.reject(&(&1.id == target.id))
            |> List.insert_at(clamped - 1, target)

          repack_positions(reordered)

          Storybox.Stories.StorySpineEntry
          |> Ash.Query.filter(id == ^target.id)
          |> Ash.read_one(authorize?: false)
        end
      end
    end
  end

  # Rewrites the positions of the given entries (already in desired order) to a
  # dense 1..n sequence. To avoid transiently violating the unique
  # (story_spine_id, position) index, all entries are first parked at negative
  # positions, then assigned their final values.
  defp repack_positions(ordered_entries) do
    ordered_entries
    |> Enum.with_index(1)
    |> Enum.each(fn {entry, index} ->
      entry
      |> Ash.Changeset.for_update(:set_position, %{position: -index})
      |> Ash.update!(authorize?: false)
    end)

    ordered_entries
    |> Enum.with_index(1)
    |> Enum.each(fn {entry, index} ->
      entry
      |> Ash.Changeset.for_update(:set_position, %{position: index})
      |> Ash.update!(authorize?: false)
    end)
  end
end
