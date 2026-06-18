defmodule Storybox.Stories.TaskGeneration do
  require Ash.Query

  alias Storybox.Stories.{
    Character,
    CharacterView,
    CharacterViewVersion,
    Scene,
    ScriptView,
    ScriptViewVersion,
    SequencePiece,
    SequenceView,
    Segment,
    SynopsisView,
    SynopsisViewVersion,
    Task,
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
  Called after a Piece :create_version action. Creates :review tasks for stale
  ViewVersions (a pinned segment points to an older version — compatibility is
  uncertain, so the question is re-pin or refine) and :refinement tasks for
  downstream stale Pieces (derived from an older source, genuinely outdated).
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

    # Downstream: SequencePieces derived from this synopsis sequence that are stale
    stale_seq_pieces =
      SequencePiece
      |> Ash.Query.filter(sequence_id == ^piece.sequence_id)
      |> Ash.read!(authorize?: false)
      |> Enum.filter(fn sp ->
        not is_nil(sp.source_synopsis_piece_id) and
          Staleness.piece_stale?(sp.id, :sequence_piece)
      end)

    Enum.each(stale_seq_pieces, fn sp ->
      sequence_view =
        SequenceView
        |> Ash.Query.filter(sequence_id == ^sp.sequence_id)
        |> Ash.read_one!(authorize?: false)

      if sequence_view do
        # One open refinement per View — nil target_view_version_id signals agent
        # to investigate all stale pieces in the view rather than a specific VV.
        maybe_create_downstream_refinement_task(
          sequence_view.id,
          "sequence_vv",
          :story,
          story_id,
          piece.id,
          "synopsis_piece",
          piece.version_number,
          story_id
        )
      end
    end)

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

    # Downstream: ScriptPieces derived from sequences in this piece's lineage
    seq_piece_ids =
      SequencePiece
      |> Ash.Query.filter(sequence_id == ^piece.sequence_id)
      |> Ash.read!(authorize?: false)
      |> Enum.map(& &1.id)

    stale_script_pieces =
      case seq_piece_ids do
        [] ->
          []

        ids ->
          Storybox.Stories.ScriptPiece
          |> Ash.Query.filter(source_sequence_piece_id in ^ids)
          |> Ash.read!(authorize?: false)
          |> Enum.filter(&Staleness.piece_stale?(&1.id, :script_piece))
      end

    Enum.each(stale_script_pieces, fn sp ->
      script_view =
        ScriptView
        |> Ash.Query.filter(scene_id == ^sp.scene_id)
        |> Ash.read_one!(authorize?: false)

      if script_view do
        scene =
          Scene
          |> Ash.Query.filter(id == ^sp.scene_id)
          |> Ash.read_one!(authorize?: false)

        maybe_create_downstream_refinement_task(
          script_view.id,
          "script_vv",
          :scene,
          sp.scene_id,
          piece.id,
          "sequence_piece",
          piece.version_number,
          scene.story_id
        )
      end
    end)

    :ok
  end

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

  # Creates a :refinement task for a downstream stale piece, deduped by
  # target_view_id. target_view_version_id is nil — the agent investigates all
  # stale pieces in that view rather than a specific VV snapshot.
  defp maybe_create_downstream_refinement_task(
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
        type == :refinement and
          target_view_id == ^view_id and
          is_nil(target_view_version_id) and
          (status == :pending or status == :in_progress)
      )
      |> Ash.read!(authorize?: false)

    if Enum.empty?(existing) do
      Task
      |> Ash.Changeset.for_create(:create, %{
        story_id: story_id,
        type: :refinement,
        status: :pending,
        component_type: component_type,
        component_id: component_id,
        target_view_id: view_id,
        target_view_version_id: nil,
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
