defmodule Storybox.Stories.Staleness do
  @moduledoc """
  Computed View-staleness — no stored flags.

  All staleness is derived on read by walking a ViewVersion's Segments and
  comparing each Pin's `pin_version_at_creation` against the current latest
  version of the referent (via
  `Storybox.Stories.Segment.pin_target_latest_version/1`). A ViewVersion is
  stale when it pins an older version of one of its referents.

  This is the only cross-layer change signal: cross-layer relationships are
  positional, not derivational, so Pieces carry no provenance and there is no
  Piece-level staleness.

  ## Example

      iex> Storybox.Stories.Staleness.view_version_stale?(vv.id, :script_vv)
      false

      iex> Storybox.Stories.Staleness.story_stale_summary(story.id)
      %{view_versions: [%{id: "...", type: :script_vv}]}
  """

  require Ash.Query

  alias Storybox.Stories.{
    Scene,
    ScriptView,
    ScriptViewVersion,
    Segment,
    SequenceView,
    SequenceViewVersion,
    StoryScriptView,
    StoryScriptViewVersion,
    SynopsisView,
    SynopsisViewVersion,
    ThroughlineViewVersion,
    TreatmentView,
    TreatmentViewVersion
  }

  @spec view_version_stale?(Ecto.UUID.t(), atom()) :: boolean()
  def view_version_stale?(view_version_id, :synopsis_vv) do
    stale_segments?(view_version_id, :synopsis_vv) or
      throughline_harness_stale?(view_version_id)
  end

  def view_version_stale?(view_version_id, view_version_type) do
    stale_segments?(view_version_id, view_version_type)
  end

  defp stale_segments?(view_version_id, view_version_type) do
    view_version_id
    |> stale_segments(view_version_type)
    |> Enum.any?()
  end

  # A SynopsisViewVersion is harness-stale when a newer Through-line ViewVersion
  # exists than the one it was cut against. A nil harness reference (no
  # Through-line View/VV at cut time) is never stale.
  defp throughline_harness_stale?(synopsis_vv_id) do
    synopsis_vv =
      SynopsisViewVersion
      |> Ash.Query.filter(id == ^synopsis_vv_id)
      |> Ash.read_one!(authorize?: false)

    case synopsis_vv && synopsis_vv.throughline_view_version_id do
      nil ->
        false

      recorded_id ->
        case ThroughlineViewVersion
             |> Ash.Query.filter(id == ^recorded_id)
             |> Ash.read_one!(authorize?: false) do
          nil ->
            false

          recorded ->
            latest_version =
              ThroughlineViewVersion
              |> Ash.Query.filter(throughline_view_id == ^recorded.throughline_view_id)
              |> Ash.read!(authorize?: false)
              |> Enum.map(& &1.version_number)
              |> Enum.max(fn -> recorded.version_number end)

            recorded.version_number < latest_version
        end
    end
  end

  @spec view_version_stale_segments(Ecto.UUID.t(), atom()) :: [Segment.t()]
  def view_version_stale_segments(view_version_id, view_version_type) do
    stale_segments(view_version_id, view_version_type)
  end

  @spec piece_stale?(Ecto.UUID.t(), atom()) :: boolean()
  def piece_stale?(_piece_id, piece_type)
      when piece_type in [:synopsis_piece, :character_piece, :world_piece],
      do: false

  def piece_stale?(_piece_id, piece_type) do
    raise ArgumentError, "piece_stale?/2 received unknown piece_type #{inspect(piece_type)}"
  end

  @spec story_stale_summary(Ecto.UUID.t()) :: %{
          view_versions: [%{id: Ecto.UUID.t(), type: atom()}]
        }
  def story_stale_summary(story_id) do
    %{view_versions: stale_view_versions_for_story(story_id)}
  end

  defp stale_segments(view_version_id, view_version_type) do
    Segment
    |> Ash.Query.filter(
      view_version_id == ^view_version_id and view_version_type == ^view_version_type
    )
    |> Ash.read!(authorize?: false)
    |> Enum.filter(&segment_stale?/1)
  end

  defp segment_stale?(%{pin_version_at_creation: nil}), do: false

  defp segment_stale?(segment) do
    case Segment.pin_target_latest_version(segment) do
      nil -> false
      latest -> segment.pin_version_at_creation < latest
    end
  end

  defp stale_view_versions_for_story(story_id) do
    treatment_vvs = treatment_view_versions(story_id) |> tag(:treatment_vv)
    synopsis_vvs = synopsis_view_versions(story_id) |> tag(:synopsis_vv)
    sequence_vvs = sequence_view_versions(story_id) |> tag(:sequence_vv)
    script_vvs = script_view_versions(story_id) |> tag(:script_vv)
    story_script_vvs = story_script_view_versions(story_id) |> tag(:story_script_vv)

    (treatment_vvs ++ synopsis_vvs ++ sequence_vvs ++ script_vvs ++ story_script_vvs)
    |> Enum.filter(fn %{id: id, type: type} -> view_version_stale?(id, type) end)
  end

  defp tag(records, type), do: Enum.map(records, fn r -> %{id: r.id, type: type} end)

  defp treatment_view_versions(story_id) do
    case TreatmentView
         |> Ash.Query.filter(story_id == ^story_id)
         |> Ash.read_one!(authorize?: false) do
      nil ->
        []

      tv ->
        TreatmentViewVersion
        |> Ash.Query.filter(treatment_view_id == ^tv.id)
        |> Ash.read!(authorize?: false)
    end
  end

  defp synopsis_view_versions(story_id) do
    case SynopsisView
         |> Ash.Query.filter(story_id == ^story_id)
         |> Ash.read_one!(authorize?: false) do
      nil ->
        []

      sv ->
        SynopsisViewVersion
        |> Ash.Query.filter(synopsis_view_id == ^sv.id)
        |> Ash.read!(authorize?: false)
    end
  end

  defp sequence_view_versions(story_id) do
    sequence_view_ids =
      SequenceView
      |> Ash.Query.filter(story_id == ^story_id)
      |> Ash.read!(authorize?: false)
      |> Enum.map(& &1.id)

    case sequence_view_ids do
      [] ->
        []

      ids ->
        SequenceViewVersion
        |> Ash.Query.filter(sequence_view_id in ^ids)
        |> Ash.read!(authorize?: false)
    end
  end

  defp script_view_versions(story_id) do
    scene_ids = scene_ids_for_story(story_id)

    case scene_ids do
      [] ->
        []

      ids ->
        script_view_ids =
          ScriptView
          |> Ash.Query.filter(scene_id in ^ids)
          |> Ash.read!(authorize?: false)
          |> Enum.map(& &1.id)

        case script_view_ids do
          [] ->
            []

          svids ->
            ScriptViewVersion
            |> Ash.Query.filter(script_view_id in ^svids)
            |> Ash.read!(authorize?: false)
        end
    end
  end

  defp story_script_view_versions(story_id) do
    case StoryScriptView
         |> Ash.Query.filter(story_id == ^story_id)
         |> Ash.read_one!(authorize?: false) do
      nil ->
        []

      ssv ->
        StoryScriptViewVersion
        |> Ash.Query.filter(story_script_view_id == ^ssv.id)
        |> Ash.read!(authorize?: false)
    end
  end

  defp scene_ids_for_story(story_id) do
    Scene
    |> Ash.Query.filter(story_id == ^story_id)
    |> Ash.read!(authorize?: false)
    |> Enum.map(& &1.id)
  end
end
