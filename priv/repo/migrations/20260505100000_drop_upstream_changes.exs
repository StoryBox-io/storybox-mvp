defmodule Storybox.Repo.Migrations.DropUpstreamChanges do
  use Ecto.Migration

  def up do
    drop table(:upstream_changes)
  end

  def down do
    create table(:upstream_changes, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :piece_version_type, :text, null: false
      add :piece_version_id, :uuid, null: false
      add :component_type, :text, null: false
      add :component_id, :uuid, null: false
      add :version_before, :text
      add :version_after, :text
      add :acknowledged, :boolean, null: false, default: false

      add :inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")
    end
  end
end
