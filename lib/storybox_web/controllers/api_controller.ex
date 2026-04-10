defmodule StoryboxWeb.ApiController do
  use StoryboxWeb, :controller

  def ping(conn, %{"story_id" => story_id}) do
    json(conn, %{status: "ok", story_id: story_id})
  end
end
