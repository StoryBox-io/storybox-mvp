defmodule Storybox.Repo.Migrations.CreateTokens do
  use Ecto.Migration

  def up do
    create table(:tokens, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :jti, :text, null: false
      add :subject, :text, null: false
      add :expires_at, :utc_datetime
      add :purpose, :text, null: false
      add :extra_data, :map
      add :created_by_id, :uuid
      add :resource, :text

      timestamps(type: :utc_datetime)
    end

    create index(:tokens, [:jti], unique: true)
  end

  def down do
    drop table(:tokens)
  end
end