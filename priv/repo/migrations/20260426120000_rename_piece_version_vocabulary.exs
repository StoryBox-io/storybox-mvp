defmodule Storybox.Repo.Migrations.RenamePieceVersionVocabulary do
  use Ecto.Migration

  def up do
    rename table(:scene_pieces), to: table(:script_views)
    rename table(:scene_versions), to: table(:script_pieces)
    rename table(:sequence_pieces), to: table(:treatment_views)
    rename table(:sequence_versions), to: table(:treatment_pieces)
    rename table(:synopsis_versions), to: table(:synopsis_views)

    # On a fresh DB, scene_component already dropped sequence_piece_id from
    # scene_pieces (now script_views). Guard the rename to handle both orderings.
    execute """
    DO $$
    BEGIN
      IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'script_views'
          AND column_name = 'sequence_piece_id'
      ) THEN
        ALTER TABLE script_views RENAME COLUMN sequence_piece_id TO treatment_view_id;
      END IF;
    END
    $$
    """

    rename table(:script_pieces), :scene_piece_id, to: :script_view_id
    rename table(:treatment_pieces), :sequence_piece_id, to: :treatment_view_id
  end

  def down do
    rename table(:treatment_pieces), :treatment_view_id, to: :sequence_piece_id
    rename table(:script_pieces), :script_view_id, to: :scene_piece_id

    execute """
    DO $$
    BEGIN
      IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'script_views'
          AND column_name = 'treatment_view_id'
      ) THEN
        ALTER TABLE script_views RENAME COLUMN treatment_view_id TO sequence_piece_id;
      END IF;
    END
    $$
    """

    rename table(:synopsis_views), to: table(:synopsis_versions)
    rename table(:treatment_pieces), to: table(:sequence_versions)
    rename table(:treatment_views), to: table(:sequence_pieces)
    rename table(:script_pieces), to: table(:scene_versions)
    rename table(:script_views), to: table(:scene_pieces)
  end
end
