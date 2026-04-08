defmodule StoryboxWeb.ErrorJSONTest do
  use StoryboxWeb.ConnCase, async: true

  test "renders 404" do
    assert StoryboxWeb.ErrorJSON.render("404.json", %{}) == %{errors: %{detail: "Not Found"}}
  end

  test "renders 500" do
    assert StoryboxWeb.ErrorJSON.render("500.json", %{}) ==
             %{errors: %{detail: "Internal Server Error"}}
  end
end
