defmodule StoryboxWeb.Plugs.ApiAuth do
  @moduledoc """
  Authenticates API requests via a bearer token.

  On success, assigns `:current_user` and `:current_story` to the conn.

  Story-scope enforcement (Option A): if the route has a `:story_id` path param,
  the token's `story_id` must match — otherwise the request is rejected with 403.
  This centralises the check so controllers don't need to repeat it.
  """

  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  require Ash.Query

  alias Storybox.Accounts.ApiToken

  def init(opts), do: opts

  def call(conn, _opts) do
    with {:ok, raw_token} <- extract_token(conn),
         {:ok, api_token} <- ApiToken.verify(raw_token),
         :ok <- check_story_scope(conn, api_token),
         {:ok, user} <- load_user(api_token.user_id),
         {:ok, story} <- load_story(api_token.story_id) do
      conn
      |> assign(:current_user, user)
      |> assign(:current_story, story)
    else
      {:error, :not_found} -> unauthorized(conn)
      {:error, :expired} -> unauthorized(conn)
      {:error, :story_mismatch} -> forbidden(conn)
      _ -> unauthorized(conn)
    end
  end

  defp extract_token(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] -> {:ok, String.trim(token)}
      _ -> {:error, :not_found}
    end
  end

  defp check_story_scope(conn, api_token) do
    case conn.path_params["story_id"] do
      nil -> :ok
      story_id -> if api_token.story_id == story_id, do: :ok, else: {:error, :story_mismatch}
    end
  end

  defp load_user(user_id) do
    case Storybox.Accounts.User
         |> Ash.Query.filter(id == ^user_id)
         |> Ash.read_one(authorize?: false) do
      {:ok, user} when not is_nil(user) -> {:ok, user}
      _ -> {:error, :user_not_found}
    end
  end

  defp load_story(story_id) do
    case Storybox.Stories.Story
         |> Ash.Query.filter(id == ^story_id)
         |> Ash.read_one(authorize?: false) do
      {:ok, story} when not is_nil(story) -> {:ok, story}
      _ -> {:error, :story_not_found}
    end
  end

  defp unauthorized(conn) do
    conn
    |> put_status(401)
    |> json(%{error: "unauthorized"})
    |> halt()
  end

  defp forbidden(conn) do
    conn
    |> put_status(403)
    |> json(%{error: "forbidden"})
    |> halt()
  end
end
