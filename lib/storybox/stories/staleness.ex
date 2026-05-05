defmodule Storybox.Stories.Staleness do
  @moduledoc """
  Computed staleness — no stored flags.

  All staleness is derived on read by walking Segments and comparing each
  Pin's `pin_version_at_creation` against the current latest version of the
  referent (via `Storybox.Stories.Segment.pin_target_latest_version/1`), and
  by comparing each Piece's `source_version_at_creation` against the current
  latest version in the source's lineage.

  Pieces with no provenance — `:synopsis_piece`, `:character_piece`, and
  `:world_piece` — always return `false` from `piece_stale?/2`. This is
  intentional: synopsis is the root of the piece-derivation chain, and
  character/world pieces have no upstream lineage to compare against.

  ## Example

      iex> Storybox.Stories.Staleness.view_version_stale?(vv.id, :script_vv)
      false

      iex> Storybox.Stories.Staleness.piece_stale?(piece.id, :script_piece)
      true


      iex> Storybox.Stories.Staleness.story_stale_summary(story.id)
      %{view_versions: [%{id: "...", type: :script_vv}], pieces: []}
  """

  require Ash.Query

  alias Storybox.Stories.{
    Scene,
    ScriptPiece,
    ScriptView,
    ScriptViewVersion,
    Segment,
    SequencePiece,
    SequenceView,
    SequenceViewVersion,
    StoryScriptView,
    StoryScriptViewVersion,
    SynopsisPiece,
    SynopsisView,
    SynopsisViewVersion,
    TreatmentView,
    TreatmentViewVersion
  }

  @spec view_version_stale?(Ecto.UUID.t(), atom()) :: boolean()
  def view_version_stale?(view_version_id, view_version_type) do
    view_version_id
    |> stale_segments(view_version_type)
    |> Enum.any?()
  end

  @spec view_version_stale_segments(Ecto.UUID.t(), atom()) :: [Segment.t()]
  def view_version_stale_segments(view_version_id, view_version_type) do
    stale_segments(view_version_id, view_version_type)
  end

  @spec piece_stale?(Ecto.UUID.t(), atom()) :: boolean()
  def piece_stale?(piece_id, :script_piece) do
    piece =
      ScriptPiece
      |> Ash.Query.filter(id == ^piece_id)
      |> Ash.read_one!(authorize?: false)

    case piece.source_sequence_piece_id do
      nil ->
        false

      source_id ->
        source =
          SequencePiece
          |> Ash.Query.filter(id == ^source_id)
          |> Ash.read_one!(authorize?: false)

        latest =
          SequencePiece
          |> Ash.Query.filter(sequence_id == ^source.sequence_id)
          |> Ash.read!(authorize?: false)
          |> Enum.map(& &1.version_number)
          |> Enum.max(fn -> 0 end)

        piece.source_version_at_creation < latest
    end
  end

  def piece_stale?(piece_id, :sequence_piece) do
    piece =
      SequencePiece
      |> Ash.Query.filter(id == ^piece_id)
      |> Ash.read_one!(authorize?: false)

    case piece.source_synopsis_piece_id do
      nil ->
        false

      source_id ->
        source =
          SynopsisPiece
          |> Ash.Query.filter(id == ^source_id)
          |> Ash.read_one!(authorize?: false)

        latest =
          SynopsisPiece
          |> Ash.Query.filter(sequence_id == ^source.sequence_id)
          |> Ash.read!(authorize?: false)
          |> Enum.map(& &1.version_number)
          |> Enum.max(fn -> 0 end)

        piece.source_version_at_creation < latest
    end
  end

  def piece_stale?(_piece_id, piece_type)
      when piece_type in [:synopsis_piece, :character_piece, :world_piece],
      do: false

  def piece_stale?(_piece_id, piece_type) do
    raise ArgumentError, "piece_stale?/2 received unknown piece_type #{inspect(piece_type)}"
  end

  @spec story_stale_summary(Ecto.UUID.t()) :: %{
          view_versions: [%{id: Ecto.UUID.t(), type: atom()}],
          pieces: [%{id: Ecto.UUID.t(), type: atom()}]
        }
  def story_stale_summary(story_id) do
    %{
      view_versions: stale_view_versions_for_story(story_id),
      pieces: stale_pieces_for_story(story_id)
    }
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

  defp stale_pieces_for_story(story_id) do
    sequence_pieces =
      SequencePiece
      |> Ash.Query.filter(story_id == ^story_id)
      |> Ash.read!(authorize?: false)
      |> Enum.filter(&piece_stale?(&1.id, :sequence_piece))
      |> Enum.map(&%{id: &1.id, type: :sequence_piece})

    scene_ids = scene_ids_for_story(story_id)

    script_pieces =
      case scene_ids do
        [] ->
          []

        ids ->
          ScriptPiece
          |> Ash.Query.filter(scene_id in ^ids)
          |> Ash.read!(authorize?: false)
          |> Enum.filter(&piece_stale?(&1.id, :script_piece))
          |> Enum.map(&%{id: &1.id, type: :script_piece})
      end

    sequence_pieces ++ script_pieces
  end

  defp scene_ids_for_story(story_id) do
    Scene
    |> Ash.Query.filter(story_id == ^story_id)
    |> Ash.read!(authorize?: false)
    |> Enum.map(& &1.id)
  end
end
