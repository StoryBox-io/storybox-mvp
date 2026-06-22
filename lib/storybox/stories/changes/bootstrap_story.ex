defmodule Storybox.Stories.Changes.BootstrapStory do
  use Ash.Resource.Change

  alias Storybox.Stories.{
    TreatmentView,
    SynopsisView,
    StorySpine
  }

  # Registers an after_action hook that runs inside Ash's transaction for
  # Story.create, atomically bootstrapping the skeletal Story-wide structure.
  # Any {:error, _} returned by bootstrap/2 propagates up and causes Ash to
  # roll back the entire transaction.
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, &bootstrap/2)
  end

  # Lazy bootstrap: a new Story starts with zero Sequences and no eager layer
  # cuts. We only ensure the Story-wide skeleton — TreatmentView, SynopsisView,
  # and an (empty) StorySpine. The first Sequence created at any layer
  # materializes its own spine entry (see Sequence.:create), and layer cuts read
  # the live spine order on demand.
  defp bootstrap(_changeset, story) do
    with {:ok, _tv} <- ensure_treatment_view(story.id),
         {:ok, _sv} <- ensure_synopsis_view(story.id),
         {:ok, _spine} <- ensure_story_spine(story.id) do
      {:ok, story}
    end
  end

  defp ensure_treatment_view(story_id) do
    TreatmentView
    |> Ash.ActionInput.for_action(:ensure_for_story, %{story_id: story_id})
    |> Ash.run_action(authorize?: false)
  end

  defp ensure_synopsis_view(story_id) do
    SynopsisView
    |> Ash.ActionInput.for_action(:ensure_for_story, %{story_id: story_id})
    |> Ash.run_action(authorize?: false)
  end

  defp ensure_story_spine(story_id) do
    StorySpine
    |> Ash.ActionInput.for_action(:ensure_for_story, %{story_id: story_id})
    |> Ash.run_action(authorize?: false)
  end
end
