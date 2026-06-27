defmodule Storybox.Stories.TaskGeneration do
  require Ash.Query

  alias Storybox.Stories.{
    Character,
    CharacterView,
    CharacterViewVersion,
    Scene,
    ScriptView,
    ScriptViewVersion,
    Segment,
    StoryScriptView,
    StoryScriptViewVersion,
    SynopsisView,
    SynopsisViewVersion,
    Task,
    ThroughlineViewVersion,
    TreatmentView,
    TreatmentViewVersion,
    World,
    WorldView,
    WorldViewVersion
  }

  alias Storybox.Stories.Staleness

  @doc """
  Called after a VV :cut action. Finds nil-pin segments in the new VV and
  creates one :creation task per nil-pin segment.
  """
  def after_cut(vv_id, vv_type, target_view_id, component_type, component_id, story_id) do
    nil_pin_segments =
      Segment
      |> Ash.Query.filter(view_version_id == ^vv_id and view_version_type == ^vv_type)
      |> Ash.read!(authorize?: false)
      |> Enum.filter(&is_nil(&1.pin_id))

    Enum.each(nil_pin_segments, fn segment ->
      Task
      |> Ash.Changeset.for_create(:create, %{
        story_id: story_id,
        type: :creation,
        status: :pending,
        component_type: component_type,
        component_id: component_id,
        target_view_id: target_view_id,
        target_view_version_id: vv_id,
        target_view_type: Atom.to_string(vv_type),
        target_scene_id: segment.scene_id
      })
      |> Ash.create(authorize?: false)
    end)

    :ok
  end

  @doc """
  Called after a Through-line VV :cut. The harness is the roughest control and
  reaches the whole synopsis: any Through-line re-cut flags every existing
  SynopsisViewVersion that now reads harness-stale, generating a :review task
  per stale VV (deduped by target VV). Review-all — no topology pruning.
  """
  def after_throughline_vv_cut(throughline_vv_id, story_id) do
    throughline_vv =
      ThroughlineViewVersion
      |> Ash.Query.filter(id == ^throughline_vv_id)
      |> Ash.read_one!(authorize?: false)

    synopsis_view =
      SynopsisView
      |> Ash.Query.filter(story_id == ^story_id)
      |> Ash.read_one!(authorize?: false)

    if synopsis_view && throughline_vv do
      svvs =
        SynopsisViewVersion
        |> Ash.Query.filter(synopsis_view_id == ^synopsis_view.id)
        |> Ash.read!(authorize?: false)

      Enum.each(svvs, fn svv ->
        if Staleness.view_version_stale?(svv.id, :synopsis_vv) do
          maybe_create_review_task(
            svv.id,
            synopsis_view.id,
            "synopsis_vv",
            :story,
            story_id,
            throughline_vv_id,
            "throughline_vv",
            throughline_vv.version_number,
            story_id
          )
        end
      end)
    end

    :ok
  end

  @doc """
  Called after a Synopsis VV :cut. Synopsis is the rougher on-spine layer above
  treatment: any Synopsis re-cut flags every existing TreatmentViewVersion that
  now reads cross-layer-stale, generating a :review task per stale VV (deduped by
  target VV). Review-all — no topology pruning.
  """
  def after_synopsis_vv_cut(synopsis_vv_id, story_id) do
    synopsis_vv =
      SynopsisViewVersion
      |> Ash.Query.filter(id == ^synopsis_vv_id)
      |> Ash.read_one!(authorize?: false)

    treatment_view =
      TreatmentView
      |> Ash.Query.filter(story_id == ^story_id)
      |> Ash.read_one!(authorize?: false)

    if treatment_view && synopsis_vv do
      tvvs =
        TreatmentViewVersion
        |> Ash.Query.filter(treatment_view_id == ^treatment_view.id)
        |> Ash.read!(authorize?: false)

      Enum.each(tvvs, fn tvv ->
        if Staleness.view_version_stale?(tvv.id, :treatment_vv) do
          maybe_create_review_task(
            tvv.id,
            treatment_view.id,
            "treatment_vv",
            :story,
            story_id,
            synopsis_vv_id,
            "synopsis_vv",
            synopsis_vv.version_number,
            story_id
          )
        end
      end)
    end

    :ok
  end

  @doc """
  Called after a Treatment VV :cut. Treatment is the rougher on-spine layer above
  the story script: any Treatment re-cut flags every existing
  StoryScriptViewVersion that now reads cross-layer-stale, generating a :review
  task per stale VV (deduped by target VV). Review-all — no topology pruning.
  """
  def after_treatment_vv_cut(treatment_vv_id, story_id) do
    treatment_vv =
      TreatmentViewVersion
      |> Ash.Query.filter(id == ^treatment_vv_id)
      |> Ash.read_one!(authorize?: false)

    story_script_view =
      StoryScriptView
      |> Ash.Query.filter(story_id == ^story_id)
      |> Ash.read_one!(authorize?: false)

    if story_script_view && treatment_vv do
      ssvvs =
        StoryScriptViewVersion
        |> Ash.Query.filter(story_script_view_id == ^story_script_view.id)
        |> Ash.read!(authorize?: false)

      Enum.each(ssvvs, fn ssvv ->
        if Staleness.view_version_stale?(ssvv.id, :story_script_vv) do
          maybe_create_review_task(
            ssvv.id,
            story_script_view.id,
            "story_script_vv",
            :story,
            story_id,
            treatment_vv_id,
            "treatment_vv",
            treatment_vv.version_number,
            story_id
          )
        end
      end)
    end

    :ok
  end

  @doc """
  Called after a Piece :create_version action. Creates :review tasks for stale
  ViewVersions (a pinned segment points to an older version — compatibility is
  uncertain, so the question is re-pin or refine).
  """
  def after_piece_version(piece, :character_piece) do
    character =
      Character
      |> Ash.Query.filter(id == ^piece.character_id)
      |> Ash.read_one!(authorize?: false)

    story_id = character.story_id

    character_view =
      CharacterView
      |> Ash.Query.filter(character_id == ^piece.character_id)
      |> Ash.read_one!(authorize?: false)

    if character_view do
      cvvs =
        CharacterViewVersion
        |> Ash.Query.filter(character_view_id == ^character_view.id)
        |> Ash.read!(authorize?: false)

      Enum.each(cvvs, fn cvv ->
        if Staleness.view_version_stale?(cvv.id, :character_vv) do
          maybe_create_review_task(
            cvv.id,
            character_view.id,
            "character_vv",
            :character,
            piece.character_id,
            piece.id,
            "character_piece",
            piece.version_number,
            story_id
          )
        end
      end)
    end

    :ok
  end

  def after_piece_version(piece, :world_piece) do
    world =
      World
      |> Ash.Query.filter(id == ^piece.world_id)
      |> Ash.read_one!(authorize?: false)

    story_id = world.story_id

    world_view =
      WorldView
      |> Ash.Query.filter(world_id == ^piece.world_id)
      |> Ash.read_one!(authorize?: false)

    if world_view do
      wvvs =
        WorldViewVersion
        |> Ash.Query.filter(world_view_id == ^world_view.id)
        |> Ash.read!(authorize?: false)

      Enum.each(wvvs, fn wvv ->
        if Staleness.view_version_stale?(wvv.id, :world_vv) do
          maybe_create_review_task(
            wvv.id,
            world_view.id,
            "world_vv",
            :world,
            piece.world_id,
            piece.id,
            "world_piece",
            piece.version_number,
            story_id
          )
        end
      end)
    end

    :ok
  end

  def after_piece_version(piece, :synopsis_piece) do
    story_id = piece.story_id

    synopsis_view =
      SynopsisView
      |> Ash.Query.filter(story_id == ^story_id)
      |> Ash.read_one!(authorize?: false)

    if synopsis_view do
      svvs =
        SynopsisViewVersion
        |> Ash.Query.filter(synopsis_view_id == ^synopsis_view.id)
        |> Ash.read!(authorize?: false)

      Enum.each(svvs, fn svv ->
        if Staleness.view_version_stale?(svv.id, :synopsis_vv) do
          maybe_create_review_task(
            svv.id,
            synopsis_view.id,
            "synopsis_vv",
            :story,
            story_id,
            piece.id,
            "synopsis_piece",
            piece.version_number,
            story_id
          )
        end
      end)
    end

    :ok
  end

  def after_piece_version(piece, :sequence_piece) do
    story_id = piece.story_id

    # TreatmentViewVersions pin SequencePieces; check them for staleness
    treatment_view =
      TreatmentView
      |> Ash.Query.filter(story_id == ^story_id)
      |> Ash.read_one!(authorize?: false)

    if treatment_view do
      tvvs =
        TreatmentViewVersion
        |> Ash.Query.filter(treatment_view_id == ^treatment_view.id)
        |> Ash.read!(authorize?: false)

      Enum.each(tvvs, fn tvv ->
        if Staleness.view_version_stale?(tvv.id, :treatment_vv) do
          maybe_create_review_task(
            tvv.id,
            treatment_view.id,
            "treatment_vv",
            :story,
            story_id,
            piece.id,
            "sequence_piece",
            piece.version_number,
            story_id
          )
        end
      end)
    end

    :ok
  end

  # Through-line pieces deliberately generate no tasks yet: the cascade into
  # synopsis staleness is a separate ticket. This explicit no-op keeps
  # ThroughlinePiece.create_version green until that cascade lands.
  def after_piece_version(_piece, :throughline_piece), do: :ok

  def after_piece_version(piece, :script_piece) do
    scene =
      Scene
      |> Ash.Query.filter(id == ^piece.scene_id)
      |> Ash.read_one!(authorize?: false)

    story_id = scene.story_id

    script_view =
      ScriptView
      |> Ash.Query.filter(scene_id == ^piece.scene_id)
      |> Ash.read_one!(authorize?: false)

    if script_view do
      svvs =
        ScriptViewVersion
        |> Ash.Query.filter(script_view_id == ^script_view.id)
        |> Ash.read!(authorize?: false)

      Enum.each(svvs, fn svv ->
        if Staleness.view_version_stale?(svv.id, :script_vv) do
          maybe_create_review_task(
            svv.id,
            script_view.id,
            "script_vv",
            :scene,
            piece.scene_id,
            piece.id,
            "script_piece",
            piece.version_number,
            story_id
          )
        end
      end)
    end

    :ok
  end

  # Creates a :review task targeting a specific stale VV, deduped by
  # target_view_version_id: at most one open review task per VV at a time.
  # A stale pin may still be compatible with the new version, so the task is a
  # question (re-pin or refine?) rather than a forced :refinement.
  defp maybe_create_review_task(
         vv_id,
         view_id,
         view_type_str,
         component_type,
         component_id,
         triggering_piece_id,
         triggering_piece_type_str,
         triggering_piece_version,
         story_id
       ) do
    existing =
      Task
      |> Ash.Query.filter(
        type == :review and
          target_view_version_id == ^vv_id and
          (status == :pending or status == :in_progress)
      )
      |> Ash.read!(authorize?: false)

    if Enum.empty?(existing) do
      Task
      |> Ash.Changeset.for_create(:create, %{
        story_id: story_id,
        type: :review,
        status: :pending,
        component_type: component_type,
        component_id: component_id,
        target_view_id: view_id,
        target_view_version_id: vv_id,
        target_view_type: view_type_str,
        triggered_by_piece_id: triggering_piece_id,
        triggered_by_piece_type: triggering_piece_type_str,
        triggered_by_piece_version: triggering_piece_version
      })
      |> Ash.create(authorize?: false)
    end

    :ok
  end
end
