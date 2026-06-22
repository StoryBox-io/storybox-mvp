defmodule Storybox.Stories.Sequence do
  use Ash.Resource,
    domain: Storybox.Stories,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "sequences"
    repo Storybox.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string, allow_nil?: false, public?: true
    attribute :slug, :string, allow_nil?: false, public?: true

    create_timestamp :inserted_at
  end

  relationships do
    belongs_to :story, Storybox.Stories.Story, allow_nil?: false, public?: true
    has_one :sequence_view, Storybox.Stories.SequenceView, public?: true
  end

  identities do
    identity :unique_slug_per_story, [:story_id, :slug]
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:story_id, :name, :slug]

      # A Sequence materializes its place in the running order: register it on
      # the Story's StorySpine (created if absent) as the next entry. Runs inside
      # Story-create's transaction, so a failure rolls the Sequence back with it.
      change fn changeset, _context ->
        Ash.Changeset.after_action(changeset, fn _changeset, sequence ->
          with {:ok, spine} <- ensure_spine(sequence.story_id),
               {:ok, _entry} <- add_spine_entry(spine.id, sequence.id) do
            {:ok, sequence}
          end
        end)
      end
    end

    update :update do
      accept [:name]
    end
  end

  defp ensure_spine(story_id) do
    Storybox.Stories.StorySpine
    |> Ash.ActionInput.for_action(:ensure_for_story, %{story_id: story_id})
    |> Ash.run_action(authorize?: false)
  end

  defp add_spine_entry(story_spine_id, sequence_id) do
    Storybox.Stories.StorySpine
    |> Ash.ActionInput.for_action(:add_entry, %{
      story_spine_id: story_spine_id,
      sequence_id: sequence_id
    })
    |> Ash.run_action(authorize?: false)
  end
end
