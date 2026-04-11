defmodule StoryboxWeb.ConnCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a connection.

  Such tests rely on `Phoenix.ConnTest` and also
  import other functionality to make it easier
  to build common data structures and query the data layer.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use StoryboxWeb.ConnCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      # The default endpoint for testing
      @endpoint StoryboxWeb.Endpoint

      use StoryboxWeb, :verified_routes

      # Import conveniences for testing with connections
      import Plug.Conn
      import Phoenix.ConnTest
      import StoryboxWeb.ConnCase
    end
  end

  setup tags do
    Storybox.DataCase.setup_sandbox(tags)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  @doc """
  Stores a user in the Plug session so that LiveView tests can mount
  as an authenticated user via the AshAuthentication.Phoenix.LiveSession hook.
  """
  def log_in_user(conn, user) do
    {:ok, token, _claims} = AshAuthentication.Jwt.token_for_user(user)

    :ok =
      AshAuthentication.TokenResource.Actions.store_token(
        Storybox.Accounts.Token,
        %{"token" => token, "purpose" => "user"},
        context: %{private: %{ash_authentication?: true}}
      )

    user = %{user | __metadata__: Map.put(user.__metadata__, :token, token)}

    conn
    |> Plug.Test.init_test_session(%{})
    |> AshAuthentication.Phoenix.Plug.store_in_session(user)
  end
end
