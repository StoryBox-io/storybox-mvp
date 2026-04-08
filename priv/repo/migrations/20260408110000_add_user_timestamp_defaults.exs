defmodule Storybox.Repo.Migrations.AddUserTimestampDefaults do
  @moduledoc """
  The users table was created by a plain Ecto migration without DB-level timestamp defaults.
  AshPostgres does not include timestamps in INSERT statements when they are not declared
  as Ash attributes, so PostgreSQL must supply the default. This migration adds those defaults.
  """

  use Ecto.Migration

  def up do
    execute("ALTER TABLE users ALTER COLUMN inserted_at SET DEFAULT (now() AT TIME ZONE 'utc')")
    execute("ALTER TABLE users ALTER COLUMN updated_at SET DEFAULT (now() AT TIME ZONE 'utc')")
  end

  def down do
    execute("ALTER TABLE users ALTER COLUMN inserted_at DROP DEFAULT")
    execute("ALTER TABLE users ALTER COLUMN updated_at DROP DEFAULT")
  end
end
