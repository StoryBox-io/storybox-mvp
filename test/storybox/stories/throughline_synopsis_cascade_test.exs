defmodule Storybox.Stories.ThroughlineSynopsisCascadeTest do
  @moduledoc """
  Cascade: cutting a new Through-line ViewVersion makes existing
  SynopsisViewVersions read harness-stale and queues :review (never :refinement)
  tasks — via the view-level harness reference on SynopsisViewVersion, not a
  per-Sequence segment.
  """
  use Storybox.DataCase

  require Ash.Query

  alias Storybox.Stories.{
    Staleness,
    Story,
    SynopsisPiece,
    SynopsisView,
    SynopsisViewVersion,
    Task,
    ThroughlineView,
    ThroughlineViewVersion
  }

  setup do
    {:ok, user} =
      Storybox.Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "cascade_test@example.com",
        password: "password123!",
        password_confirmation: "password123!"
      })
      |> Ash.create()

    {:ok, story} =
      Story
      |> Ash.Changeset.for_create(:create, %{title: "Cascade Story", user_id: user.id})
      |> Ash.create()

    {:ok, synopsis_view} =
      SynopsisView
      |> Ash.ActionInput.for_action(:ensure_for_story, %{story_id: story.id})
      |> Ash.run_action()

    %{story: story, synopsis_view: synopsis_view}
  end

  defp ensure_throughline_view(story_id) do
    {:ok, tv} =
      ThroughlineView
      |> Ash.ActionInput.for_action(:ensure_for_story, %{story_id: story_id})
      |> Ash.run_action()

    tv
  end

  defp cut_throughline_vv(throughline_view_id) do
    {:ok, tvv} =
      ThroughlineViewVersion
      |> Ash.ActionInput.for_action(:cut, %{throughline_view_id: throughline_view_id})
      |> Ash.run_action()

    tvv
  end

  defp cut_synopsis_vv(synopsis_view_id) do
    {:ok, svv} =
      SynopsisViewVersion
      |> Ash.ActionInput.for_action(:cut, %{synopsis_view_id: synopsis_view_id})
      |> Ash.run_action()

    svv
  end

  defp review_tasks_for(vv_id) do
    Task
    |> Ash.Query.filter(target_view_version_id == ^vv_id and type == :review)
    |> Ash.read!(authorize?: false)
  end

  describe "SynopsisViewVersion.cut records the harness snapshot" do
    test "records the current latest Through-line VV id", %{
      story: story,
      synopsis_view: synopsis_view
    } do
      tv = ensure_throughline_view(story.id)
      _tvv1 = cut_throughline_vv(tv.id)
      tvv2 = cut_throughline_vv(tv.id)

      svv = cut_synopsis_vv(synopsis_view.id)

      assert svv.throughline_view_version_id == tvv2.id
    end

    test "records nil when the story has no Through-line View", %{
      synopsis_view: synopsis_view
    } do
      svv = cut_synopsis_vv(synopsis_view.id)

      assert is_nil(svv.throughline_view_version_id)
    end

    test "records nil when a Through-line View exists but has no VVs yet", %{
      story: story,
      synopsis_view: synopsis_view
    } do
      _tv = ensure_throughline_view(story.id)

      svv = cut_synopsis_vv(synopsis_view.id)

      assert is_nil(svv.throughline_view_version_id)
    end
  end

  describe "view_version_stale?/2 harness clause" do
    test "false when no harness reference recorded and segments are current", %{
      synopsis_view: synopsis_view
    } do
      svv = cut_synopsis_vv(synopsis_view.id)

      refute Staleness.view_version_stale?(svv.id, :synopsis_vv)
    end

    test "false when the recorded Through-line VV is still the latest", %{
      story: story,
      synopsis_view: synopsis_view
    } do
      tv = ensure_throughline_view(story.id)
      _tvv1 = cut_throughline_vv(tv.id)

      svv = cut_synopsis_vv(synopsis_view.id)

      refute Staleness.view_version_stale?(svv.id, :synopsis_vv)
    end

    test "true once a newer Through-line VV than the recorded one exists", %{
      story: story,
      synopsis_view: synopsis_view
    } do
      tv = ensure_throughline_view(story.id)
      _tvv1 = cut_throughline_vv(tv.id)

      svv = cut_synopsis_vv(synopsis_view.id)

      # Re-cut the harness: now a newer Through-line VV exists than svv recorded.
      _tvv2 = cut_throughline_vv(tv.id)

      assert Staleness.view_version_stale?(svv.id, :synopsis_vv)
    end

    test "also reports segment staleness independently of the harness", %{
      story: story,
      synopsis_view: synopsis_view
    } do
      {:ok, sequence} =
        Storybox.Stories.Sequence
        |> Ash.Changeset.for_create(:create, %{
          name: "Act One",
          slug: "act-one",
          story_id: story.id
        })
        |> Ash.create()

      {:ok, _p1} =
        SynopsisPiece
        |> Ash.Changeset.for_create(:create, %{
          story_id: story.id,
          sequence_id: sequence.id,
          content_uri: "storybox://s/act-one/v1.fountain",
          version_number: 1
        })
        |> Ash.create()

      # No Through-line View, so the harness reference is nil — staleness here can
      # only come from the segment path.
      svv = cut_synopsis_vv(synopsis_view.id)

      refute Staleness.view_version_stale?(svv.id, :synopsis_vv)

      {:ok, _p2} =
        SynopsisPiece
        |> Ash.Changeset.for_create(:create, %{
          story_id: story.id,
          sequence_id: sequence.id,
          content_uri: "storybox://s/act-one/v2.fountain",
          version_number: 2
        })
        |> Ash.create()

      assert Staleness.view_version_stale?(svv.id, :synopsis_vv)
    end
  end

  describe "after_throughline_vv_cut cascade" do
    test "cutting a new Through-line VV creates a :review task for each existing SynopsisViewVersion",
         %{story: story, synopsis_view: synopsis_view} do
      tv = ensure_throughline_view(story.id)
      _tvv1 = cut_throughline_vv(tv.id)

      svv = cut_synopsis_vv(synopsis_view.id)

      assert review_tasks_for(svv.id) == []

      _tvv2 = cut_throughline_vv(tv.id)

      [task] = review_tasks_for(svv.id)
      assert task.type == :review
      assert task.target_view_version_id == svv.id
      assert task.target_view_type == "synopsis_vv"
      assert task.component_type == :story
      assert task.component_id == story.id
      assert task.triggered_by_piece_type == "throughline_vv"
    end

    test "no :refinement task is created by the cascade", %{
      story: story,
      synopsis_view: synopsis_view
    } do
      tv = ensure_throughline_view(story.id)
      _tvv1 = cut_throughline_vv(tv.id)
      svv = cut_synopsis_vv(synopsis_view.id)
      _tvv2 = cut_throughline_vv(tv.id)

      refinement_tasks =
        Task
        |> Ash.Query.filter(target_view_version_id == ^svv.id and type == :refinement)
        |> Ash.read!(authorize?: false)

      assert refinement_tasks == []
    end

    test "dedup — a second Through-line re-cut does not create a duplicate review task", %{
      story: story,
      synopsis_view: synopsis_view
    } do
      tv = ensure_throughline_view(story.id)
      _tvv1 = cut_throughline_vv(tv.id)
      svv = cut_synopsis_vv(synopsis_view.id)

      _tvv2 = cut_throughline_vv(tv.id)
      _tvv3 = cut_throughline_vv(tv.id)

      assert length(review_tasks_for(svv.id)) == 1
    end

    test "a fresh SynopsisViewVersion cut against the latest harness is not flagged", %{
      story: story,
      synopsis_view: synopsis_view
    } do
      tv = ensure_throughline_view(story.id)
      _tvv1 = cut_throughline_vv(tv.id)
      svv1 = cut_synopsis_vv(synopsis_view.id)

      _tvv2 = cut_throughline_vv(tv.id)
      # svv1 is now stale and flagged; svv2 records tvv2 (the latest) and stays fresh.
      svv2 = cut_synopsis_vv(synopsis_view.id)

      assert length(review_tasks_for(svv1.id)) == 1
      assert review_tasks_for(svv2.id) == []
      refute Staleness.view_version_stale?(svv2.id, :synopsis_vv)
    end
  end

  describe "story_stale_summary/1" do
    test "surfaces a harness-stale SynopsisViewVersion", %{
      story: story,
      synopsis_view: synopsis_view
    } do
      tv = ensure_throughline_view(story.id)
      _tvv1 = cut_throughline_vv(tv.id)
      svv = cut_synopsis_vv(synopsis_view.id)
      _tvv2 = cut_throughline_vv(tv.id)

      summary = Staleness.story_stale_summary(story.id)
      stale_ids = Enum.map(summary.view_versions, & &1.id)

      assert svv.id in stale_ids
      assert Enum.any?(summary.view_versions, &(&1.type == :synopsis_vv))
    end
  end
end
