defmodule Storybox.Stories.TaskGenerationTest do
  @moduledoc """
  On-spine cross-layer cascade: cutting a new SynopsisViewVersion makes existing
  TreatmentViewVersions read cross-layer-stale and queues :review (never
  :refinement) tasks; cutting a new TreatmentViewVersion does the same for
  StoryScriptViewVersions — via the view-level cross-layer reference recorded at
  cut time, not a per-Sequence segment.
  """
  use Storybox.DataCase

  require Ash.Query

  alias Storybox.Stories.{
    Story,
    StoryScriptView,
    StoryScriptViewVersion,
    SynopsisView,
    SynopsisViewVersion,
    Task,
    TaskGeneration,
    TreatmentView,
    TreatmentViewVersion
  }

  setup do
    {:ok, user} =
      Storybox.Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "task_generation_test@example.com",
        password: "password123!",
        password_confirmation: "password123!"
      })
      |> Ash.create()

    {:ok, story} =
      Story
      |> Ash.Changeset.for_create(:create, %{title: "Cascade Story", user_id: user.id})
      |> Ash.create()

    # Story bootstrap ensures TreatmentView and SynopsisView; StoryScriptView is
    # ensured on demand.
    %{story: story}
  end

  defp synopsis_view_id(story_id) do
    SynopsisView
    |> Ash.Query.filter(story_id == ^story_id)
    |> Ash.read_one!(authorize?: false)
    |> Map.fetch!(:id)
  end

  defp treatment_view_id(story_id) do
    TreatmentView
    |> Ash.Query.filter(story_id == ^story_id)
    |> Ash.read_one!(authorize?: false)
    |> Map.fetch!(:id)
  end

  defp ensure_story_script_view(story_id) do
    {:ok, ssv} =
      StoryScriptView
      |> Ash.ActionInput.for_action(:ensure_for_story, %{story_id: story_id})
      |> Ash.run_action()

    ssv
  end

  defp cut_synopsis_vv(story_id) do
    {:ok, svv} =
      SynopsisViewVersion
      |> Ash.ActionInput.for_action(:cut, %{synopsis_view_id: synopsis_view_id(story_id)})
      |> Ash.run_action()

    svv
  end

  defp cut_treatment_vv(story_id) do
    {:ok, tvv} =
      TreatmentViewVersion
      |> Ash.ActionInput.for_action(:cut, %{treatment_view_id: treatment_view_id(story_id)})
      |> Ash.run_action()

    tvv
  end

  defp cut_story_script_vv(ssv_id) do
    {:ok, ssvv} =
      StoryScriptViewVersion
      |> Ash.ActionInput.for_action(:cut, %{story_script_view_id: ssv_id})
      |> Ash.run_action()

    ssvv
  end

  defp review_tasks_for(vv_id) do
    Task
    |> Ash.Query.filter(target_view_version_id == ^vv_id and type == :review)
    |> Ash.read!(authorize?: false)
  end

  describe "after_synopsis_vv_cut/2 (synopsis → treatment)" do
    test "creates a :review task for a stale TreatmentViewVersion", %{story: story} do
      _svv1 = cut_synopsis_vv(story.id)
      tvv = cut_treatment_vv(story.id)

      assert review_tasks_for(tvv.id) == []

      svv2 = cut_synopsis_vv(story.id)

      [task] = review_tasks_for(tvv.id)
      assert task.type == :review
      assert task.target_view_version_id == tvv.id
      assert task.target_view_type == "treatment_vv"
      assert task.component_type == :story
      assert task.component_id == story.id
      assert task.triggered_by_piece_type == "synopsis_vv"
      assert task.triggered_by_piece_version == svv2.version_number
    end

    test "does not create a duplicate when a pending task already exists", %{story: story} do
      _svv1 = cut_synopsis_vv(story.id)
      tvv = cut_treatment_vv(story.id)

      _svv2 = cut_synopsis_vv(story.id)
      _svv3 = cut_synopsis_vv(story.id)

      assert length(review_tasks_for(tvv.id)) == 1
    end

    test "creates no :refinement task", %{story: story} do
      _svv1 = cut_synopsis_vv(story.id)
      tvv = cut_treatment_vv(story.id)
      _svv2 = cut_synopsis_vv(story.id)

      refinement_tasks =
        Task
        |> Ash.Query.filter(target_view_version_id == ^tvv.id and type == :refinement)
        |> Ash.read!(authorize?: false)

      assert refinement_tasks == []
    end

    test "is a no-op when the story has no TreatmentViewVersion", %{story: story} do
      # A Synopsis cut with no TreatmentViewVersion in existence creates no review
      # tasks (the cascade only flags VVs that already exist).
      svv = cut_synopsis_vv(story.id)

      treatment_review_tasks =
        Task
        |> Ash.Query.filter(
          story_id == ^story.id and type == :review and target_view_type == "treatment_vv"
        )
        |> Ash.read!(authorize?: false)

      assert treatment_review_tasks == []
      assert TaskGeneration.after_synopsis_vv_cut(svv.id, story.id) == :ok
    end
  end

  describe "after_treatment_vv_cut/2 (treatment → story script)" do
    test "creates a :review task for a stale StoryScriptViewVersion", %{story: story} do
      ssv = ensure_story_script_view(story.id)

      _tvv1 = cut_treatment_vv(story.id)
      ssvv = cut_story_script_vv(ssv.id)

      assert review_tasks_for(ssvv.id) == []

      tvv2 = cut_treatment_vv(story.id)

      [task] = review_tasks_for(ssvv.id)
      assert task.type == :review
      assert task.target_view_version_id == ssvv.id
      assert task.target_view_type == "story_script_vv"
      assert task.component_type == :story
      assert task.component_id == story.id
      assert task.triggered_by_piece_type == "treatment_vv"
      assert task.triggered_by_piece_version == tvv2.version_number
    end

    test "does not create a duplicate when a pending task already exists", %{story: story} do
      ssv = ensure_story_script_view(story.id)

      _tvv1 = cut_treatment_vv(story.id)
      ssvv = cut_story_script_vv(ssv.id)

      _tvv2 = cut_treatment_vv(story.id)
      _tvv3 = cut_treatment_vv(story.id)

      assert length(review_tasks_for(ssvv.id)) == 1
    end

    test "is a no-op when the story has no StoryScriptView", %{story: story} do
      # No StoryScriptView ensured, so there are no StoryScriptViewVersions to flag.
      tvv = cut_treatment_vv(story.id)

      assert TaskGeneration.after_treatment_vv_cut(tvv.id, story.id) == :ok

      story_script_review_tasks =
        Task
        |> Ash.Query.filter(
          story_id == ^story.id and type == :review and target_view_type == "story_script_vv"
        )
        |> Ash.read!(authorize?: false)

      assert story_script_review_tasks == []
    end
  end
end
