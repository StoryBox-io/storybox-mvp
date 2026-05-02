defmodule Storybox.Repo.Migrations.RenamePieceVersionVocabulary do
  use Ecto.Migration

  def change do
    rename table(:scene_pieces), to: table(:script_views)
    rename table(:scene_versions), to: table(:script_pieces)
    rename table(:sequence_pieces), to: table(:treatment_views)
    rename table(:sequence_versions), to: table(:treatment_pieces)
    rename table(:synopsis_versions), to: table(:synopsis_views)

    rename table(:script_views), :sequence_piece_id, to: :treatment_view_id
    rename table(:script_pieces), :scene_piece_id, to: :script_view_id
    rename table(:treatment_pieces), :sequence_piece_id, to: :treatment_view_id
  end
end
