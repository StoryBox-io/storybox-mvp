defmodule Storybox.Repo.Migrations.DropScriptSnapshots do
  use Ecto.Migration

  def up do
    drop constraint(:script_snapshots, "script_snapshots_story_id_fkey")

    drop table(:script_snapshots)
  end

  def down do
    create table(:script_snapshots, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :name, :text, null: false
      add :entries, :map, default: %{}

      add :inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :story_id,
          references(:stories,
            column: :id,
            name: "script_snapshots_story_id_fkey",
            type: :uuid,
            prefix: "public"
          ),
          null: false
    end
  end
end
