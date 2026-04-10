defmodule Storybox.Accounts.User do
  use Ash.Resource,
    domain: Storybox.Accounts,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshAuthentication]

  postgres do
    table "users"
    repo Storybox.Repo
  end

  authentication do
    strategies do
      password :password do
        identity_field(:email)
        hashed_password_field(:hashed_password)
      end
    end

    tokens do
      enabled?(true)
      token_resource(Storybox.Accounts.Token)
      require_token_presence_for_authentication?(true)

      signing_secret(fn _, _ ->
        Application.fetch_env(:storybox, :token_signing_secret)
      end)
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :email, :ci_string, allow_nil?: false, public?: true
    attribute :hashed_password, :string, allow_nil?: true, sensitive?: true
  end

  actions do
    defaults [:read]
  end

  identities do
    identity :unique_email, [:email]
  end
end
