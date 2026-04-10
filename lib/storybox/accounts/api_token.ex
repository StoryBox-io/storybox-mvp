defmodule Storybox.Accounts.ApiToken do
  use Ash.Resource,
    domain: Storybox.Accounts,
    data_layer: AshPostgres.DataLayer

  require Ash.Query

  postgres do
    table "api_tokens"
    repo Storybox.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :token_hash, :string, allow_nil?: false, public?: false
    attribute :label, :string, allow_nil?: true, public?: true
    attribute :story_id, :uuid, allow_nil?: false, public?: true
    attribute :user_id, :uuid, allow_nil?: false, public?: true
    attribute :expires_at, :utc_datetime_usec, allow_nil?: true, public?: true
    attribute :last_used_at, :utc_datetime_usec, allow_nil?: true, public?: true

    timestamps()
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:label, :story_id, :user_id, :expires_at]
      argument :raw_token, :string, allow_nil?: false

      change fn changeset, _ ->
        raw_token = Ash.Changeset.get_argument(changeset, :raw_token)
        Ash.Changeset.force_change_attribute(changeset, :token_hash, hash_token(raw_token))
      end
    end

    update :touch_last_used do
      accept [:last_used_at]
    end
  end

  @doc """
  Generates a new API token for the given attributes.

  Returns `{:ok, raw_token, record}` where `raw_token` is the one-time-visible
  plaintext token the caller must store — it is never persisted.
  """
  def generate(attrs) do
    raw_token = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)

    with {:ok, record} <-
           __MODULE__
           |> Ash.Changeset.for_create(:create, Map.put(attrs, :raw_token, raw_token))
           |> Ash.create(authorize?: false) do
      {:ok, raw_token, record}
    end
  end

  @doc """
  Verifies a raw bearer token.

  Returns `{:ok, api_token}` on success, `{:error, :not_found}` for an unknown
  token, or `{:error, :expired}` for an expired one.
  """
  def verify(raw_token) do
    token_hash = hash_token(raw_token)

    with {:ok, token} when not is_nil(token) <-
           __MODULE__
           |> Ash.Query.filter(token_hash == ^token_hash)
           |> Ash.read_one(authorize?: false),
         :ok <- check_expiry(token) do
      token
      |> Ash.Changeset.for_update(:touch_last_used, %{last_used_at: DateTime.utc_now()})
      |> Ash.update(authorize?: false)

      {:ok, token}
    else
      {:ok, nil} -> {:error, :not_found}
      err -> err
    end
  end

  defp hash_token(raw_token) do
    :crypto.hash(:sha256, raw_token) |> Base.encode16(case: :lower)
  end

  defp check_expiry(%{expires_at: nil}), do: :ok

  defp check_expiry(%{expires_at: exp}) do
    if DateTime.compare(exp, DateTime.utc_now()) == :lt do
      {:error, :expired}
    else
      :ok
    end
  end
end
