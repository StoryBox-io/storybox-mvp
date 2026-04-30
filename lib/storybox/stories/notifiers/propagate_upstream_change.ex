defmodule Storybox.Stories.Notifiers.PropagateUpstreamChange do
  use Ash.Notifier

  require Ash.Query

  alias Storybox.Stories.{
    Scene,
    ScriptView,
    ScriptPiece,
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
    scene_ids =
      Scene
      |> Ash.Query.filter(story_id == ^story_id)
      |> Ash.read!()
      |> Enum.map(& &1.id)

    script_views =
      case scene_ids do
        [] ->
          []

        ids ->
          ScriptView
          |> Ash.Query.filter(scene_id in ^ids)
          |> Ash.read!()
      end

    for script_view <- script_views do
      script_pieces =
        ScriptPiece
        |> Ash.Query.filter(script_view_id == ^script_view.id)
        |> Ash.read!()

      for sp <- script_pieces do
        sp
        |> Ash.Changeset.for_update(:mark_stale, %{})
        |> Ash.update!()

        UpstreamChange
        |> Ash.Changeset.for_create(:create, %{
          piece_version_type: :script_piece,
          piece_version_id: sp.id,
          component_type: component_type,
          component_id: component_id,
          version_before: version_before,
          version_after: version_after
        })
        |> Ash.create!()
      end
    end

    :ok
  end
end
