defmodule Storybox.Repo do
  use Ecto.Repo,
    otp_app: :storybox,
    adapter: Ecto.Adapters.Postgres
end
