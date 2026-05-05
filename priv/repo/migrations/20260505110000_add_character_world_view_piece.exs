defmodule Storybox.Repo.Migrations.AddCharacterWorldViewPiece do
  use Ecto.Migration

  def up do
    create table(:character_pieces, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :content_uri, :text, null: false
      add :version_number, :bigint, null: false

      add :inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :character_id,
          references(:characters,
            column: :id,
            name: "character_pieces_character_id_fkey",
            type: :uuid,
            prefix: "public"
          ),
          null: false
    end

    create unique_index(:character_pieces, [:character_id, :version_number],
             name: "character_pieces_unique_version_per_character_index"
           )

    create table(:character_views, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true

      add :inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :character_id,
          references(:characters,
            column: :id,
            name: "character_views_character_id_fkey",
            type: :uuid,
            prefix: "public"
          ),
          null: false
    end

    create unique_index(:character_views, [:character_id],
             name: "character_views_unique_character_index"
           )

    create table(:character_view_versions, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :version_number, :bigint, null: false

      add :inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :character_view_id,
          references(:character_views,
            column: :id,
            name: "character_view_versions_character_view_id_fkey",
            type: :uuid,
            prefix: "public"
          ),
          null: false
    end

    create unique_index(:character_view_versions, [:character_view_id, :version_number],
             name: "character_view_versions_unique_version_per_view_index"
           )

    create table(:world_pieces, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :content_uri, :text, null: false
      add :version_number, :bigint, null: false

      add :inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :world_id,
          references(:worlds,
            column: :id,
            name: "world_pieces_world_id_fkey",
            type: :uuid,
            prefix: "public"
          ),
          null: false
    end

    create unique_index(:world_pieces, [:world_id, :version_number],
             name: "world_pieces_unique_version_per_world_index"
           )

    create table(:world_views, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true

      add :inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :world_id,
          references(:worlds,
            column: :id,
            name: "world_views_world_id_fkey",
            type: :uuid,
            prefix: "public"
          ),
          null: false
    end

    create unique_index(:world_views, [:world_id], name: "world_views_unique_world_index")

    create table(:world_view_versions, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :version_number, :bigint, null: false

      add :inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :world_view_id,
          references(:world_views,
            column: :id,
            name: "world_view_versions_world_view_id_fkey",
            type: :uuid,
            prefix: "public"
          ),
          null: false
    end

    create unique_index(:world_view_versions, [:world_view_id, :version_number],
             name: "world_view_versions_unique_version_per_view_index"
           )

    alter table(:characters) do
      remove :essence
      remove :voice
      remove :contradictions
    end

    alter table(:worlds) do
      remove :history
      remove :rules
      remove :subtext
    end
  end

  def down do
    alter table(:worlds) do
      add :history, :text
      add :rules, :text
      add :subtext, :text
    end

    alter table(:characters) do
      add :essence, :text
      add :voice, :text
      add :contradictions, {:array, :text}
    end

    drop_if_exists unique_index(:world_view_versions, [:world_view_id, :version_number],
                     name: "world_view_versions_unique_version_per_view_index"
                   )

    drop constraint(:world_view_versions, "world_view_versions_world_view_id_fkey")
    drop table(:world_view_versions)

    drop_if_exists unique_index(:world_views, [:world_id], name: "world_views_unique_world_index")

    drop constraint(:world_views, "world_views_world_id_fkey")
    drop table(:world_views)

    drop_if_exists unique_index(:world_pieces, [:world_id, :version_number],
                     name: "world_pieces_unique_version_per_world_index"
                   )

    drop constraint(:world_pieces, "world_pieces_world_id_fkey")
    drop table(:world_pieces)

    drop_if_exists unique_index(:character_view_versions, [:character_view_id, :version_number],
                     name: "character_view_versions_unique_version_per_view_index"
                   )

    drop constraint(:character_view_versions, "character_view_versions_character_view_id_fkey")
    drop table(:character_view_versions)

    drop_if_exists unique_index(:character_views, [:character_id],
                     name: "character_views_unique_character_index"
                   )

    drop constraint(:character_views, "character_views_character_id_fkey")
    drop table(:character_views)

    drop_if_exists unique_index(:character_pieces, [:character_id, :version_number],
                     name: "character_pieces_unique_version_per_character_index"
                   )

    drop constraint(:character_pieces, "character_pieces_character_id_fkey")
    drop table(:character_pieces)
  end
end
