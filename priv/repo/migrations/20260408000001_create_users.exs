defmodule Storybox.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def up do
    execute "CREATE EXTENSION IF NOT EXISTS citext"

    create table(:users, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :email, :citext, null: false
      add :hashed_password, :text

      timestamps(type: :utc_datetime)
    end

    create index(:users, [:email], unique: true)
  end

  def down do
    drop table(:users)
  end
end
