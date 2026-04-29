defmodule Storybox.Repo.Migrations.SyncSnapshotDrift do
  @moduledoc """
  Snapshot reconciliation only — see issue #105.

  Codegen wanted to emit FK constraint renames (treatment_views, treatment_pieces,
  synopsis_views, script_pieces) and a `script_views` column swap (drop position +
  treatment_view_id, add scene_id). The DB already has all of those changes,
  applied by:

    - 20260426090910_scene_component        (FK renames; script_views columns)
    - 20260426120000_rename_piece_version_vocabulary
                                            (table renames; PG auto-renamed FK identifiers)

  This migration exists only so the regenerated snapshots have an applied
  timestamp to anchor against. It is intentionally a no-op.
  """

  use Ecto.Migration

  def up do
    :ok
  end

  def down do
    :ok
  end
end
