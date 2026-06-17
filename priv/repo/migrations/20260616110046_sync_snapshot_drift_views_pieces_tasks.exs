defmodule Storybox.Repo.Migrations.SyncSnapshotDriftViewsPiecesTasks do
  @moduledoc """
  Snapshot reconciliation only — see issue #174.

  Codegen wanted to emit `characters`/`worlds` column drops (essence, voice,
  contradictions / history, rules, subtext) and CREATE TABLE for the character
  and world view/version/piece tables plus `tasks`. The DB already has all of
  those changes, applied by:

    - 20260505110000_add_character_world_view_piece
                                            (column drops; character/world
                                             view, version, and piece tables)
    - 20260509120000_add_tasks              (tasks table and indexes)

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
