defmodule StoryboxWeb.StoryListLiveTest do
  use StoryboxWeb.ConnCase

  import Phoenix.LiveViewTest

  setup do
    {:ok, alice} =
      Storybox.Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "alice@example.com",
        password: "password123!",
        password_confirmation: "password123!"
      })
      |> Ash.create()

    {:ok, bob} =
      Storybox.Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "bob@example.com",
        password: "password123!",
        password_confirmation: "password123!"
      })
      |> Ash.create()

    {:ok, redemption_arc} =
      Storybox.Stories.Story
      |> Ash.Changeset.for_create(:create, %{
        title: "Redemption Arc",
        logline: "A man seeks redemption",
        user_id: alice.id
      })
      |> Ash.create()

    {:ok, the_heist} =
      Storybox.Stories.Story
      |> Ash.Changeset.for_create(:create, %{
        title: "The Heist",
        user_id: alice.id
      })
      |> Ash.create()

    {:ok, _bobs_story} =
      Storybox.Stories.Story
      |> Ash.Changeset.for_create(:create, %{
        title: "Bob's Story",
        user_id: bob.id
      })
      |> Ash.create()

    %{
      alice: alice,
      bob: bob,
      redemption_arc: redemption_arc,
      the_heist: the_heist
    }
  end

  describe "unauthenticated access" do
    test "redirects to sign-in when not logged in", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/sign-in"}}} = live(conn, "/")
    end
  end

  describe "authenticated story list" do
    test "shows Alice's story titles", %{conn: conn, alice: alice} do
      conn = log_in_user(conn, alice)
      {:ok, _view, html} = live(conn, "/")

      assert html =~ "Redemption Arc"
      assert html =~ "The Heist"
    end

    test "shows the logline for Redemption Arc", %{conn: conn, alice: alice} do
      conn = log_in_user(conn, alice)
      {:ok, _view, html} = live(conn, "/")

      assert html =~ "A man seeks redemption"
    end

    test "does not show Bob's Story to Alice", %{conn: conn, alice: alice} do
      conn = log_in_user(conn, alice)
      {:ok, _view, html} = live(conn, "/")

      refute html =~ "Bob&#39;s Story"
      refute html =~ "Bob's Story"
    end

    test "shows empty state when user has no stories", %{conn: conn} do
      # Bob has a story in setup but we create a fresh user with no stories
      {:ok, empty_user} =
        Storybox.Accounts.User
        |> Ash.Changeset.for_create(:register_with_password, %{
          email: "empty@example.com",
          password: "password123!",
          password_confirmation: "password123!"
        })
        |> Ash.create()

      conn = log_in_user(conn, empty_user)
      {:ok, _view, html} = live(conn, "/")

      assert html =~ "No stories yet"
    end

    test "sign-out link is present in the layout", %{conn: conn, alice: alice} do
      conn = log_in_user(conn, alice)
      {:ok, _view, html} = live(conn, "/")

      assert html =~ "/sign-out"
    end

    test "shows Alice's email in the layout", %{conn: conn, alice: alice} do
      conn = log_in_user(conn, alice)
      {:ok, _view, html} = live(conn, "/")

      assert html =~ "alice@example.com"
    end
  end
end
