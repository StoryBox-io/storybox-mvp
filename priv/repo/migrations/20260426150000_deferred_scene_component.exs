defmodule Storybox.Repo.Migrations.DeferredSceneComponent do
  @moduledoc """
  Completes the scene_component work on a fresh DB.

  Migration 20260426090910 (scene_component) references treatment_views,
  treatment_pieces, synopsis_views, script_views, and script_pieces, which
  only exist after 20260426120000 (rename_piece_version_vocabulary) runs.
  On a fresh DB the rename migration has a later timestamp, so scene_component
  skips those steps via a runtime guard. This migration runs after the rename
  and applies all the deferred steps idempotently.

  On an existing DB (where scene_component ran against the pre-rename tables)
  every step is a no-op: FK constraints already have the correct names, tables
  already exist, columns are already in their final state.
  """

  use Ecto.Migration

  def up do
    execute """
    DO $$
    BEGIN
      -- FK renames: skip if already done (constraint name is the new name).
      IF NOT EXISTS (
        SELECT FROM pg_constraint
        WHERE conname = 'treatment_views_story_id_fkey'
          AND conrelid = (SELECT oid FROM pg_class WHERE relname = 'treatment_views'
                          AND relnamespace = 'public'::regnamespace)
      ) THEN
        ALTER TABLE treatment_views DROP CONSTRAINT IF EXISTS "sequence_pieces_story_id_fkey";
        ALTER TABLE treatment_views
          ADD CONSTRAINT "treatment_views_story_id_fkey"
          FOREIGN KEY (story_id) REFERENCES stories(id);
      END IF;

      IF NOT EXISTS (
        SELECT FROM pg_constraint
        WHERE conname = 'treatment_pieces_treatment_view_id_fkey'
          AND conrelid = (SELECT oid FROM pg_class WHERE relname = 'treatment_pieces'
                          AND relnamespace = 'public'::regnamespace)
      ) THEN
        ALTER TABLE treatment_pieces DROP CONSTRAINT IF EXISTS "sequence_versions_sequence_piece_id_fkey";
        ALTER TABLE treatment_pieces
          ADD CONSTRAINT "treatment_pieces_treatment_view_id_fkey"
          FOREIGN KEY (treatment_view_id) REFERENCES treatment_views(id);
      END IF;

      IF NOT EXISTS (
        SELECT FROM pg_constraint
        WHERE conname = 'synopsis_views_story_id_fkey'
          AND conrelid = (SELECT oid FROM pg_class WHERE relname = 'synopsis_views'
                          AND relnamespace = 'public'::regnamespace)
      ) THEN
        ALTER TABLE synopsis_views DROP CONSTRAINT IF EXISTS "synopsis_versions_story_id_fkey";
        ALTER TABLE synopsis_views
          ADD CONSTRAINT "synopsis_views_story_id_fkey"
          FOREIGN KEY (story_id) REFERENCES stories(id);
      END IF;

      -- treatment_view_scenes: create if absent.
      IF NOT EXISTS (
        SELECT FROM pg_tables WHERE schemaname = 'public' AND tablename = 'treatment_view_scenes'
      ) THEN
        CREATE TABLE treatment_view_scenes (
          id uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
          position bigint NOT NULL,
          inserted_at timestamptz NOT NULL DEFAULT (now() AT TIME ZONE 'utc'),
          updated_at  timestamptz NOT NULL DEFAULT (now() AT TIME ZONE 'utc'),
          treatment_view_id uuid NOT NULL
            CONSTRAINT treatment_view_scenes_treatment_view_id_fkey
            REFERENCES treatment_views(id),
          scene_id uuid NOT NULL
            CONSTRAINT treatment_view_scenes_scene_id_fkey
            REFERENCES scenes(id)
        );
      END IF;

      -- script_views: add scene_id if absent.
      IF NOT EXISTS (
        SELECT FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name   = 'script_views'
          AND column_name  = 'scene_id'
      ) THEN
        ALTER TABLE script_views
          ADD COLUMN scene_id uuid
          CONSTRAINT script_views_scene_id_fkey REFERENCES scenes(id);
      END IF;

      -- Data migration (no-op on existing DBs where treatment_view_scenes already has rows,
      -- and a true no-op on fresh DBs where script_views has no rows).
      IF NOT EXISTS (SELECT FROM treatment_view_scenes LIMIT 1) THEN
        CREATE TEMP TABLE _scene_migrations (
          script_view_id    uuid NOT NULL,
          scene_id          uuid NOT NULL,
          treatment_view_id uuid NOT NULL,
          position          bigint NOT NULL
        );

        INSERT INTO _scene_migrations (script_view_id, scene_id, treatment_view_id, position)
        SELECT sv.id, gen_random_uuid(), sv.treatment_view_id, sv.position
        FROM script_views sv
        WHERE sv.treatment_view_id IS NOT NULL;

        INSERT INTO scenes (id, title, story_id, inserted_at, updated_at)
        SELECT sm.scene_id, sv.title, tv.story_id,
               (now() AT TIME ZONE 'utc'), (now() AT TIME ZONE 'utc')
        FROM _scene_migrations sm
        JOIN script_views sv ON sv.id = sm.script_view_id
        JOIN treatment_views tv ON tv.id = sm.treatment_view_id;

        UPDATE script_views
        SET scene_id = sm.scene_id
        FROM _scene_migrations sm
        WHERE script_views.id = sm.script_view_id;

        INSERT INTO treatment_view_scenes
               (id, treatment_view_id, scene_id, position, inserted_at, updated_at)
        SELECT gen_random_uuid(), sm.treatment_view_id, sm.scene_id, sm.position,
               (now() AT TIME ZONE 'utc'), (now() AT TIME ZONE 'utc')
        FROM _scene_migrations sm;

        DROP TABLE _scene_migrations;
      END IF;

      -- Enforce NOT NULL (idempotent), drop old columns (IF EXISTS).
      ALTER TABLE script_views ALTER COLUMN scene_id SET NOT NULL;
      ALTER TABLE script_views DROP COLUMN IF EXISTS treatment_view_id;
      ALTER TABLE script_views DROP COLUMN IF EXISTS position;

      -- script_pieces FK rename: skip if already done.
      IF NOT EXISTS (
        SELECT FROM pg_constraint
        WHERE conname = 'script_pieces_script_view_id_fkey'
          AND conrelid = (SELECT oid FROM pg_class WHERE relname = 'script_pieces'
                          AND relnamespace = 'public'::regnamespace)
      ) THEN
        ALTER TABLE script_pieces DROP CONSTRAINT IF EXISTS "scene_versions_scene_piece_id_fkey";
        ALTER TABLE script_pieces
          ADD CONSTRAINT "script_pieces_script_view_id_fkey"
          FOREIGN KEY (script_view_id) REFERENCES script_views(id);
      END IF;
    END $$
    """
  end

  def down do
    execute """
    DO $$
    BEGIN
      -- Reverse only if this migration was the one that applied the changes
      -- (i.e. on a fresh DB). On existing DBs scene_component owns these changes
      -- and its own down/1 reverses them.

      -- Restore script_pieces FK name if we renamed it.
      IF NOT EXISTS (
        SELECT FROM pg_constraint
        WHERE conname = 'scene_versions_scene_piece_id_fkey'
          AND conrelid = (SELECT oid FROM pg_class WHERE relname = 'script_pieces'
                          AND relnamespace = 'public'::regnamespace)
      ) THEN
        ALTER TABLE script_pieces DROP CONSTRAINT IF EXISTS "script_pieces_script_view_id_fkey";
        BEGIN
          ALTER TABLE script_pieces
            ADD CONSTRAINT "scene_versions_scene_piece_id_fkey"
            FOREIGN KEY (script_view_id) REFERENCES script_views(id);
        EXCEPTION WHEN duplicate_object THEN NULL; END;
      END IF;

      -- Restore script_views columns if we removed them.
      IF NOT EXISTS (
        SELECT FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name   = 'script_views'
          AND column_name  = 'treatment_view_id'
      ) THEN
        ALTER TABLE script_views DROP COLUMN IF EXISTS scene_id;
        ALTER TABLE script_views ADD COLUMN position bigint NOT NULL DEFAULT 1;
        ALTER TABLE script_views ADD COLUMN treatment_view_id uuid;
      END IF;

      -- Drop treatment_view_scenes if we created it.
      IF EXISTS (
        SELECT FROM pg_tables WHERE schemaname = 'public' AND tablename = 'treatment_view_scenes'
      ) THEN
        ALTER TABLE treatment_view_scenes
          DROP CONSTRAINT IF EXISTS "treatment_view_scenes_treatment_view_id_fkey";
        ALTER TABLE treatment_view_scenes
          DROP CONSTRAINT IF EXISTS "treatment_view_scenes_scene_id_fkey";
        DROP TABLE treatment_view_scenes;
      END IF;

      -- Restore FK names if we renamed them.
      IF NOT EXISTS (
        SELECT FROM pg_constraint
        WHERE conname = 'sequence_pieces_story_id_fkey'
          AND conrelid = (SELECT oid FROM pg_class WHERE relname = 'treatment_views'
                          AND relnamespace = 'public'::regnamespace)
      ) THEN
        ALTER TABLE treatment_views DROP CONSTRAINT IF EXISTS "treatment_views_story_id_fkey";
        BEGIN
          ALTER TABLE treatment_views
            ADD CONSTRAINT "sequence_pieces_story_id_fkey"
            FOREIGN KEY (story_id) REFERENCES stories(id);
        EXCEPTION WHEN duplicate_object THEN NULL; END;
      END IF;

      IF NOT EXISTS (
        SELECT FROM pg_constraint
        WHERE conname = 'sequence_versions_sequence_piece_id_fkey'
          AND conrelid = (SELECT oid FROM pg_class WHERE relname = 'treatment_pieces'
                          AND relnamespace = 'public'::regnamespace)
      ) THEN
        ALTER TABLE treatment_pieces DROP CONSTRAINT IF EXISTS "treatment_pieces_treatment_view_id_fkey";
        BEGIN
          ALTER TABLE treatment_pieces
            ADD CONSTRAINT "sequence_versions_sequence_piece_id_fkey"
            FOREIGN KEY (treatment_view_id) REFERENCES treatment_views(id);
        EXCEPTION WHEN duplicate_object THEN NULL; END;
      END IF;

      IF NOT EXISTS (
        SELECT FROM pg_constraint
        WHERE conname = 'synopsis_versions_story_id_fkey'
          AND conrelid = (SELECT oid FROM pg_class WHERE relname = 'synopsis_views'
                          AND relnamespace = 'public'::regnamespace)
      ) THEN
        ALTER TABLE synopsis_views DROP CONSTRAINT IF EXISTS "synopsis_views_story_id_fkey";
        BEGIN
          ALTER TABLE synopsis_views
            ADD CONSTRAINT "synopsis_versions_story_id_fkey"
            FOREIGN KEY (story_id) REFERENCES stories(id);
        EXCEPTION WHEN duplicate_object THEN NULL; END;
      END IF;
    END $$
    """
  end
end
