defmodule Storybox.Repo.Migrations.AddTasks do
  use Ecto.Migration

  def up do
    create table(:tasks, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true

      add :story_id, :uuid, null: false

      add :component_type, :text, null: false
      add :component_id, :uuid, null: false
      add :target_view_id, :uuid, null: false
      add :target_view_version_id, :uuid, null: true
      add :target_view_type, :text, null: false

      add :type, :text, null: false
      add :status, :text, null: false, default: "pending"

      add :triggered_by_piece_id, :uuid, null: true
      add :triggered_by_piece_type, :text, null: true
      add :triggered_by_piece_version, :bigint, null: true

      add :inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :updated_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")
    end

    create index(:tasks, [:story_id, :status, :inserted_at],
             name: "tasks_story_id_status_inserted_at_index"
           )

    create index(:tasks, [:status, :inserted_at], name: "tasks_status_inserted_at_index")

    create index(:tasks, [:component_type, :component_id],
             name: "tasks_component_type_component_id_index"
           )

    create index(:tasks, [:target_view_id], name: "tasks_target_view_id_index")
  end

  def down do
    drop_if_exists index(:tasks, [:target_view_id], name: "tasks_target_view_id_index")

    drop_if_exists index(:tasks, [:component_type, :component_id],
                     name: "tasks_component_type_component_id_index"
                   )

    drop_if_exists index(:tasks, [:status, :inserted_at], name: "tasks_status_inserted_at_index")

    drop_if_exists index(:tasks, [:story_id, :status, :inserted_at],
                     name: "tasks_story_id_status_inserted_at_index"
                   )

    drop table(:tasks)
  end
end
