defmodule Storybox.Stories.Changes.BootstrapStory do
  use Ash.Resource.Change

  alias Storybox.Stories.{
    Sequence,
    TreatmentView,
    TreatmentViewVersion,
    SynopsisView,
    SynopsisViewVersion,
    StorySpine
  }

  # Registers an after_action hook that runs inside Ash's transaction for
  # Story.create, atomically bootstrapping the skeletal Story-wide structure.
  # Any {:error, _} returned by bootstrap/2 propagates up and causes Ash to
  # roll back the entire transaction.
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, &bootstrap/2)
  end

  defp bootstrap(_changeset, story) do
    with {:ok, seq} <- create_default_sequence(story.id),
         {:ok, tv} <- ensure_treatment_view(story.id),
         {:ok, _tvv} <- cut_treatment_view_version(tv.id),
         {:ok, sv} <- ensure_synopsis_view(story.id),
         {:ok, _svv} <- cut_synopsis_view_version(sv.id),
         {:ok, spine} <- ensure_story_spine(story.id),
         {:ok, _entry} <- add_default_sequence_to_spine(spine.id, seq.id) do
      {:ok, story}
    end
  end

  defp create_default_sequence(story_id) do
    Sequence
    |> Ash.Changeset.for_create(:create, %{
      story_id: story_id,
      name: "Sequence 1",
      slug: "sequence-1"
    })
    |> Ash.create(authorize?: false)
  end

  defp ensure_treatment_view(story_id) do
    TreatmentView
    |> Ash.ActionInput.for_action(:ensure_for_story, %{story_id: story_id})
    |> Ash.run_action(authorize?: false)
  end

  defp cut_treatment_view_version(treatment_view_id) do
    TreatmentViewVersion
    |> Ash.ActionInput.for_action(:cut, %{treatment_view_id: treatment_view_id})
    |> Ash.run_action(authorize?: false)
  end

  defp ensure_synopsis_view(story_id) do
    SynopsisView
    |> Ash.ActionInput.for_action(:ensure_for_story, %{story_id: story_id})
    |> Ash.run_action(authorize?: false)
  end

  defp cut_synopsis_view_version(synopsis_view_id) do
    SynopsisViewVersion
    |> Ash.ActionInput.for_action(:cut, %{synopsis_view_id: synopsis_view_id})
    |> Ash.run_action(authorize?: false)
  end

  defp ensure_story_spine(story_id) do
    StorySpine
    |> Ash.ActionInput.for_action(:ensure_for_story, %{story_id: story_id})
    |> Ash.run_action(authorize?: false)
  end

  defp add_default_sequence_to_spine(story_spine_id, sequence_id) do
    StorySpine
    |> Ash.ActionInput.for_action(:add_entry, %{
      story_spine_id: story_spine_id,
      sequence_id: sequence_id
    })
    |> Ash.run_action(authorize?: false)
  end
end
