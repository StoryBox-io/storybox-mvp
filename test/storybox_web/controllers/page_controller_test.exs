defmodule StoryboxWeb.PageControllerTest do
  use StoryboxWeb.ConnCase

  test "GET / redirects unauthenticated users to sign-in", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert redirected_to(conn) == ~p"/sign-in"
  end
end
