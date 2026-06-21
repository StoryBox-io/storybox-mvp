defmodule Storybox.Stories.StorySpineViewVersion do
  use Ash.Resource,
    domain: Storybox.Stories,
    data_layer: AshPostgres.DataLayer

  require Ash.Query

  postgres do
    table "story_spine_view_versions"
    repo Storybox.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :version_number, :integer, allow_nil?: false, public?: true

    create_timestamp :inserted_at
  end

  relationships do
    belongs_to :story_spine, Storybox.Stories.StorySpine, allow_nil?: false, public?: true

    has_many :story_spine_vv_entries, Storybox.Stories.StorySpineVvEntry, public?: true
  end

  identities do
    identity :unique_version_per_spine, [:story_spine_id, :version_number]
  end

  actions do
    defaults [:read]

    create :create do
      accept [:story_spine_id, :version_number]
    end

    # Cuts an immutable snapshot of the spine's current live entries. Reads the
    # live StorySpineEntry rows sorted by position, allocates the next version
    # number, and copies each entry into a StorySpineVvEntry. The spine VV has
    # no Segments and no pins, so no TaskGeneration.after_cut call.
    action :cut, :struct do
      constraints instance_of: Storybox.Stories.StorySpineViewVersion
      argument :story_spine_id, :uuid, allow_nil?: false

      run fn input, _context ->
        story_spine_id = input.arguments.story_spine_id

        live_entries =
          Storybox.Stories.StorySpineEntry
          |> Ash.Query.filter(story_spine_id == ^story_spine_id)
          |> Ash.Query.sort(:position)
          |> Ash.read!(authorize?: false)

        next_version_number =
          Storybox.Stories.StorySpineViewVersion
          |> Ash.Query.filter(story_spine_id == ^story_spine_id)
          |> Ash.read!(authorize?: false)
          |> Enum.map(& &1.version_number)
          |> Enum.max(fn -> 0 end)
          |> Kernel.+(1)

        vv =
          Storybox.Stories.StorySpineViewVersion
          |> Ash.Changeset.for_create(:create, %{
            story_spine_id: story_spine_id,
            version_number: next_version_number
          })
          |> Ash.create!(authorize?: false)

        Enum.each(live_entries, fn entry ->
          Storybox.Stories.StorySpineVvEntry
          |> Ash.Changeset.for_create(:create, %{
            story_spine_view_version_id: vv.id,
            sequence_id: entry.sequence_id,
            position: entry.position
          })
          |> Ash.create!(authorize?: false)
        end)

        {:ok, vv}
      end
    end
  end
end
