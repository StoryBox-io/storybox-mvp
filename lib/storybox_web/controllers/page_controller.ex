defmodule StoryboxWeb.PageController do
  use StoryboxWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
