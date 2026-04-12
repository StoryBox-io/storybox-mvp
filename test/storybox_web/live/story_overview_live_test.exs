defmodule StoryboxWeb.StoryOverviewLiveTest do
  use StoryboxWeb.ConnCase

  import Phoenix.LiveViewTest

  # Seed data graph:
  #
  #   alice ──► "The Grand Illusion" (story)
  #               ├── Character: "Marcel"   (essence, voice, contradictions)
  #               ├── Character: "Nora"     (essence only)
  #               ├── World                 (history, rules, subtext)
  #               ├── SynopsisVersion v1    (older)
  #               └── SynopsisVersion v2    (latest — styled green in graph)
  #
  #   bob  ──► "Bob's Story" (separate user, used for auth isolation checks)

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

    {:ok, story} =
      Storybox.Stories.Story
      |> Ash.Changeset.for_create(:create, %{
        title: "The Grand Illusion",
        logline: "Two prisoners plan an impossible escape.",
        controlling_idea: "Freedom is won through solidarity.",
        through_lines: ["preference", "theme"],
        user_id: alice.id
      })
      |> Ash.create()

    {:ok, marcel} =
      Storybox.Stories.Character
      |> Ash.Changeset.for_create(:create, %{
        name: "Marcel",
        essence: "Dignified soldier",
        voice: "Formal and restrained",
        contradictions: ["noble yet complicit", "loyal yet resigned"],
        story_id: story.id
      })
      |> Ash.create()

    {:ok, nora} =
      Storybox.Stories.Character
      |> Ash.Changeset.for_create(:create, %{
        name: "Nora",
        essence: "Pragmatic survivor",
        story_id: story.id
      })
      |> Ash.create()

    {:ok, world} =
      Storybox.Stories.World
      |> Ash.Changeset.for_create(:create, %{
        history: "Post-war Paris",
        rules: "Trust no one",
        subtext: "Loss of innocence",
        story_id: story.id
      })
      |> Ash.create()

    {:ok, sv1} =
      Storybox.Stories.SynopsisVersion
      |> Ash.Changeset.for_create(:create, %{
        story_id: story.id,
        content_uri: "storybox://stories/#{story.id}/synopsis/v1",
        version_number: 1
      })
      |> Ash.create()

    {:ok, sv2} =
      Storybox.Stories.SynopsisVersion
      |> Ash.Changeset.for_create(:create, %{
        story_id: story.id,
        content_uri: "storybox://stories/#{story.id}/synopsis/v2",
        version_number: 2
      })
      |> Ash.create()

    {:ok, bobs_story} =
      Storybox.Stories.Story
      |> Ash.Changeset.for_create(:create, %{
        title: "Bob's Story",
        user_id: bob.id
      })
      |> Ash.create()

    %{
      alice: alice,
      bob: bob,
      story: story,
      marcel: marcel,
      nora: nora,
      world: world,
      sv1: sv1,
      sv2: sv2,
      bobs_story: bobs_story
    }
  end

  describe "unauthenticated access" do
    test "redirects to sign-in when not logged in", %{conn: conn, story: story} do
      assert {:error, {:redirect, %{to: "/sign-in"}}} =
               live(conn, "/stories/#{story.id}")
    end
  end

  describe "authorization" do
    test "redirects to / when visiting another user's story", %{
      conn: conn,
      alice: alice,
      bobs_story: bobs_story
    } do
      conn = log_in_user(conn, alice)

      assert {:error, {:redirect, %{to: "/"}}} =
               live(conn, "/stories/#{bobs_story.id}")
    end

    test "redirects to / when story_id does not exist", %{conn: conn, alice: alice} do
      conn = log_in_user(conn, alice)
      fake_id = Ash.UUID.generate()

      assert {:error, {:redirect, %{to: "/"}}} =
               live(conn, "/stories/#{fake_id}")
    end
  end

  describe "story header" do
    test "renders the story title", %{conn: conn, alice: alice, story: story} do
      conn = log_in_user(conn, alice)
      {:ok, _view, html} = live(conn, "/stories/#{story.id}")

      assert html =~ "The Grand Illusion"
    end

    test "renders the logline", %{conn: conn, alice: alice, story: story} do
      conn = log_in_user(conn, alice)
      {:ok, _view, html} = live(conn, "/stories/#{story.id}")

      assert html =~ "Two prisoners plan an impossible escape."
    end

    test "renders the controlling idea", %{conn: conn, alice: alice, story: story} do
      conn = log_in_user(conn, alice)
      {:ok, _view, html} = live(conn, "/stories/#{story.id}")

      assert html =~ "Freedom is won through solidarity."
    end

    test "renders the through lines joined by comma", %{conn: conn, alice: alice, story: story} do
      conn = log_in_user(conn, alice)
      {:ok, _view, html} = live(conn, "/stories/#{story.id}")

      assert html =~ "preference, theme"
    end
  end

  describe "characters section" do
    test "lists both characters by name", %{conn: conn, alice: alice, story: story} do
      conn = log_in_user(conn, alice)
      {:ok, _view, html} = live(conn, "/stories/#{story.id}")

      assert html =~ "Marcel"
      assert html =~ "Nora"
    end

    test "shows Marcel's essence", %{conn: conn, alice: alice, story: story} do
      conn = log_in_user(conn, alice)
      {:ok, _view, html} = live(conn, "/stories/#{story.id}")

      assert html =~ "Dignified soldier"
    end

    test "shows Nora's essence", %{conn: conn, alice: alice, story: story} do
      conn = log_in_user(conn, alice)
      {:ok, _view, html} = live(conn, "/stories/#{story.id}")

      assert html =~ "Pragmatic survivor"
    end

    test "shows no characters empty state for a story with no characters", %{
      conn: conn,
      alice: alice
    } do
      {:ok, empty_story} =
        Storybox.Stories.Story
        |> Ash.Changeset.for_create(:create, %{title: "Bare Story", user_id: alice.id})
        |> Ash.create()

      conn = log_in_user(conn, alice)
      {:ok, _view, html} = live(conn, "/stories/#{empty_story.id}")

      assert html =~ "No characters defined yet."
    end
  end

  describe "world section" do
    test "shows the world history", %{conn: conn, alice: alice, story: story} do
      conn = log_in_user(conn, alice)
      {:ok, _view, html} = live(conn, "/stories/#{story.id}")

      assert html =~ "Post-war Paris"
    end

    test "shows the world rules", %{conn: conn, alice: alice, story: story} do
      conn = log_in_user(conn, alice)
      {:ok, _view, html} = live(conn, "/stories/#{story.id}")

      assert html =~ "Trust no one"
    end

    test "shows the world subtext", %{conn: conn, alice: alice, story: story} do
      conn = log_in_user(conn, alice)
      {:ok, _view, html} = live(conn, "/stories/#{story.id}")

      assert html =~ "Loss of innocence"
    end

    test "shows no world empty state for a story with no world record", %{
      conn: conn,
      alice: alice
    } do
      {:ok, worldless_story} =
        Storybox.Stories.Story
        |> Ash.Changeset.for_create(:create, %{title: "Worldless Story", user_id: alice.id})
        |> Ash.create()

      conn = log_in_user(conn, alice)
      {:ok, _view, html} = live(conn, "/stories/#{worldless_story.id}")

      assert html =~ "No world defined yet."
    end
  end

  describe "synopsis section" do
    test "shows v2 as the latest version", %{conn: conn, alice: alice, story: story} do
      conn = log_in_user(conn, alice)
      {:ok, _view, html} = live(conn, "/stories/#{story.id}")

      assert html =~ "v2"
      assert html =~ "Latest"
    end

    test "shows v1 in the version list", %{conn: conn, alice: alice, story: story} do
      conn = log_in_user(conn, alice)
      {:ok, _view, html} = live(conn, "/stories/#{story.id}")

      assert html =~ "v1"
    end

    test "shows no synopsis empty state for a story with no synopsis versions", %{
      conn: conn,
      alice: alice
    } do
      {:ok, bare_story} =
        Storybox.Stories.Story
        |> Ash.Changeset.for_create(:create, %{title: "Bare Story 2", user_id: alice.id})
        |> Ash.create()

      conn = log_in_user(conn, alice)
      {:ok, _view, html} = live(conn, "/stories/#{bare_story.id}")

      assert html =~ "No synopsis versions yet."
    end
  end

  describe "story list links" do
    test "story titles in the list link to the overview page", %{
      conn: conn,
      alice: alice,
      story: story
    } do
      conn = log_in_user(conn, alice)
      {:ok, _view, html} = live(conn, "/")

      assert html =~ "/stories/#{story.id}"
    end
  end
end
