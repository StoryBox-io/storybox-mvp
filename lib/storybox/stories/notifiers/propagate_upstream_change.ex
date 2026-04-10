defmodule Storybox.Stories.Notifiers.PropagateUpstreamChange do
  use Ash.Notifier

  require Ash.Query

  alias Storybox.Stories.{
    ScenePiece,
    SceneVersion,
    SequencePiece,
    SequenceVersion,
    UpstreamChange
  }

  @impl true
  def notify(%Ash.Notifier.Notification{
        action: %{type: :update},
        resource: resource,
        data: record,
        changeset: changeset
      }) do
    {story_id, component_type, component_id} = component_info(resource, record)
    version_before = to_string(changeset.data.updated_at)
    version_after = to_string(record.updated_at)

    propagate(story_id, component_type, component_id, version_before, version_after)
  end

  def notify(_), do: :ok

  defp component_info(Storybox.Stories.Story, record), do: {record.id, :story, record.id}

  defp component_info(Storybox.Stories.Character, record),
    do: {record.story_id, :character, record.id}

  defp component_info(Storybox.Stories.World, record), do: {record.story_id, :world, record.id}

  defp propagate(story_id, component_type, component_id, version_before, version_after) do
    sequence_pieces =
      SequencePiece
      |> Ash.Query.filter(story_id == ^story_id)
      |> Ash.read!()

    for sp <- sequence_pieces do
      sequence_versions =
        SequenceVersion
        |> Ash.Query.filter(sequence_piece_id == ^sp.id)
        |> Ash.read!()

      for sv <- sequence_versions do
        sv
        |> Ash.Changeset.for_update(:mark_stale, %{})
        |> Ash.update!()

        UpstreamChange
        |> Ash.Changeset.for_create(:create, %{
          piece_version_type: :sequence_version,
          piece_version_id: sv.id,
          component_type: component_type,
          component_id: component_id,
          version_before: version_before,
          version_after: version_after
        })
        |> Ash.create!()
      end

      scene_pieces =
        ScenePiece
        |> Ash.Query.filter(sequence_piece_id == ^sp.id)
        |> Ash.read!()

      for scene_piece <- scene_pieces do
        scene_versions =
          SceneVersion
          |> Ash.Query.filter(scene_piece_id == ^scene_piece.id)
          |> Ash.read!()

        for sv <- scene_versions do
          sv
          |> Ash.Changeset.for_update(:mark_stale, %{})
          |> Ash.update!()

          UpstreamChange
          |> Ash.Changeset.for_create(:create, %{
            piece_version_type: :scene_version,
            piece_version_id: sv.id,
            component_type: component_type,
            component_id: component_id,
            version_before: version_before,
            version_after: version_after
          })
          |> Ash.create!()
        end
      end
    end

    :ok
  end
end
