defmodule Storybox.Accounts.Token do
  use Ash.Resource,
    domain: Storybox.Accounts,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAuthentication.TokenResource]

  postgres do
    table "tokens"
    repo Storybox.Repo
  end

  actions do
    defaults [:read, :destroy]
  end
end
