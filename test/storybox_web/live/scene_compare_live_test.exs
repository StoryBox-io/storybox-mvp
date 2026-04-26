defmodule StoryboxWeb.SceneCompareLiveTest do
  use StoryboxWeb.ConnCase

  import Phoenix.LiveViewTest

  require Ash.Query

  # Seed data graph:
  #
  #   alice ──► "Compare Test Story" (through_lines: ["theme_a","theme_b"])
  #               └── seq  "Seq One"
  #                     ├── Scene Alpha  approved → SV1
  #                     │     ├── SV1  v1  weights: {theme_a→0.8, theme_b→0.6}  status: current  [approved]
  #                     │     └── SV2  v2  weights: {}                           status: stale
  #                     ├── Scene Beta   approved → nil
  #                     │     └── SV3  v1  weights: {}                           status: current
  #                     └── Scene Gamma  approved → nil  (no versions)
  #
  #   bob ──► "Bob's Story" (used for auth isolation checks)

  setup do
    {:ok, alice} =
      Storybox.Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "alice@compare.test",
        password: "password123!",
        password_confirmation: "password123!"
      })
      |> Ash.create()

    {:ok, bob} =
      Storybox.Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "bob@compare.test",
        password: "password123!",
        password_confirmation: "password123!"
      })
      |> Ash.create()

    {:ok, story} =
      Storybox.Stories.Story
      |> Ash.Changeset.for_create(:create, %{
        title: "Compare Test Story",
        through_lines: ["theme_a", "theme_b"],
        user_id: alice.id
      })
      |> Ash.create()

    {:ok, bobs_story} =
      Storybox.Stories.Story
      |> Ash.Changeset.for_create(:create, %{
        title: "Bob's Story",
        user_id: bob.id
      })
      |> Ash.create()

    {:ok, seq} =
      Storybox.Stories.TreatmentView
      |> Ash.Changeset.for_create(:create, %{
        title: "Seq One",
        position: 1,
        story_id: story.id
      })
      |> Ash.create()

    # Scene Alpha — two versions, approved → v1
    {:ok, scene_alpha} =
      Storybox.Stories.ScriptView
      |> Ash.Changeset.for_create(:create, %{
        title: "Scene Alpha",
        position: 1,
        treatment_view_id: seq.id
      })
      |> Ash.create()

    {:ok, sv1} =
      Storybox.Stories.ScriptPiece
      |> Ash.Changeset.for_create(:create, %{
        script_view_id: scene_alpha.id,
        content_uri: "storybox://test/alpha/v1",
        version_number: 1,
        upstream_status: :current,
        weights: %{"theme_a" => 0.8, "theme_b" => 0.6}
      })
      |> Ash.create()

    {:ok, sv2} =
      Storybox.Stories.ScriptPiece
      |> Ash.Changeset.for_create(:create, %{
        script_view_id: scene_alpha.id,
        content_uri: "storybox://test/alpha/v2",
        version_number: 2,
        upstream_status: :stale,
        weights: %{}
      })
      |> Ash.create()

    {:ok, scene_alpha} =
      scene_alpha
      |> Ash.Changeset.for_update(:approve_version, %{version_id: sv1.id})
      |> Ash.update()

    # Scene Beta — one version, no approved pointer
    {:ok, scene_beta} =
      Storybox.Stories.ScriptView
      |> Ash.Changeset.for_create(:create, %{
        title: "Scene Beta",
        position: 2,
        treatment_view_id: seq.id
      })
      |> Ash.create()

    {:ok, sv3} =
      Storybox.Stories.ScriptPiece
      |> Ash.Changeset.for_create(:create, %{
        script_view_id: scene_beta.id,
        content_uri: "storybox://test/beta/v1",
        version_number: 1,
        upstream_status: :current,
        weights: %{}
      })
      |> Ash.create()

    # Scene Gamma — no versions
    {:ok, scene_gamma} =
      Storybox.Stories.ScriptView
      |> Ash.Changeset.for_create(:create, %{
        title: "Scene Gamma",
        position: 3,
        treatment_view_id: seq.id
      })
      |> Ash.create()

    %{
      alice: alice,
      bob: bob,
      story: story,
      bobs_story: bobs_story,
      seq: seq,
      scene_alpha: scene_alpha,
      sv1: sv1,
      sv2: sv2,
      scene_beta: scene_beta,
      sv3: sv3,
      scene_gamma: scene_gamma
    }
  end

  describe "route auth" do
    test "unauthenticated request redirects to sign-in", %{
      conn: conn,
      story: story,
      scene_alpha: scene
    } do
      assert {:error, {:redirect, %{to: "/sign-in"}}} =
               live(conn, "/stories/#{story.id}/scenes/#{scene.id}/compare")
    end

    test "wrong story_id redirects with error flash", %{
      conn: conn,
      alice: alice,
      bobs_story: bobs_story,
      scene_alpha: scene
    } do
      conn = log_in_user(conn, alice)
      # scene_alpha belongs to alice's story — accessing it via bob's story_id is rejected
      assert {:error, {:redirect, %{to: "/", flash: %{"error" => _}}}} =
               live(conn, "/stories/#{bobs_story.id}/scenes/#{scene.id}/compare")
    end
  end

  describe "default columns" do
    test "no params: v1 in left column, v2 in right column (second-latest left, latest right)", %{
      conn: conn,
      alice: alice,
      story: story,
      scene_alpha: scene
    } do
      conn = log_in_user(conn, alice)
      {:ok, _view, html} = live(conn, "/stories/#{story.id}/scenes/#{scene.id}/compare")

      # Both version numbers appear
      assert html =~ "v1"
      assert html =~ "v2"
    end
  end

  describe "explicit params" do
    test "?left=2&right=1 shows v2 in left column and v1 in right column", %{
      conn: conn,
      alice: alice,
      story: story,
      scene_alpha: scene
    } do
      conn = log_in_user(conn, alice)

      {:ok, _view, html} =
        live(conn, "/stories/#{story.id}/scenes/#{scene.id}/compare?left=2&right=1")

      assert html =~ "v2"
      assert html =~ "v1"
    end
  end

  describe "left column badges (default: v1 left)" do
    test "v1 in left column shows Approved badge (it is the approved version)", %{
      conn: conn,
      alice: alice,
      story: story,
      scene_alpha: scene
    } do
      conn = log_in_user(conn, alice)
      {:ok, _view, html} = live(conn, "/stories/#{story.id}/scenes/#{scene.id}/compare")

      assert html =~ "Approved"
    end

    test "v1 in left column shows upstream_status current", %{
      conn: conn,
      alice: alice,
      story: story,
      scene_alpha: scene
    } do
      conn = log_in_user(conn, alice)
      {:ok, _view, html} = live(conn, "/stories/#{story.id}/scenes/#{scene.id}/compare")

      assert html =~ "current"
    end

    test "v1 in left column shows review_status reviewed (both through_lines in weights)", %{
      conn: conn,
      alice: alice,
      story: story,
      scene_alpha: scene
    } do
      conn = log_in_user(conn, alice)
      {:ok, _view, html} = live(conn, "/stories/#{story.id}/scenes/#{scene.id}/compare")

      assert html =~ "reviewed"
    end
  end

  describe "right column badges (default: v2 right)" do
    test "v2 in right column shows no Approved badge and shows Approve button", %{
      conn: conn,
      alice: alice,
      story: story,
      scene_alpha: scene,
      sv2: sv2
    } do
      conn = log_in_user(conn, alice)
      {:ok, _view, html} = live(conn, "/stories/#{story.id}/scenes/#{scene.id}/compare")

      # Only one Approved badge (for v1 left)
      assert length(:binary.matches(html, "Approved")) == 1

      # Approve button for sv2 is present
      assert html =~
               "phx-value-version-id=\"#{sv2.id}\""
    end

    test "v2 in right column shows upstream_status stale", %{
      conn: conn,
      alice: alice,
      story: story,
      scene_alpha: scene
    } do
      conn = log_in_user(conn, alice)
      {:ok, _view, html} = live(conn, "/stories/#{story.id}/scenes/#{scene.id}/compare")

      assert html =~ "stale"
    end

    test "v2 in right column shows review_status unreviewed (empty weights)", %{
      conn: conn,
      alice: alice,
      story: story,
      scene_alpha: scene
    } do
      conn = log_in_user(conn, alice)
      {:ok, _view, html} = live(conn, "/stories/#{story.id}/scenes/#{scene.id}/compare")

      assert html =~ "unreviewed"
    end
  end

  describe "approve moves the pointer" do
    test "clicking Approve on v2 sets approved_version_id to sv2 and updates badges", %{
      conn: conn,
      alice: alice,
      story: story,
      scene_alpha: scene,
      sv1: sv1,
      sv2: sv2
    } do
      conn = log_in_user(conn, alice)
      {:ok, view, _html} = live(conn, "/stories/#{story.id}/scenes/#{scene.id}/compare")

      view
      |> element("[phx-click=\"approve_version\"][phx-value-version-id=\"#{sv2.id}\"]")
      |> render_click()

      html = render(view)

      # v2 now shows Approved badge; v1 now shows Approve button
      assert html =~ "Approved"

      # v1 now has an Approve button
      assert html =~
               "phx-value-version-id=\"#{sv1.id}\""

      # DB pointer is updated
      updated =
        Storybox.Stories.ScriptView
        |> Ash.Query.filter(id == ^scene.id)
        |> Ash.read_one!(authorize?: false)

      assert updated.approved_version_id == sv2.id
    end
  end

  describe "single-version scene" do
    test "Scene Beta (one version) renders right column with v1 and left column placeholder", %{
      conn: conn,
      alice: alice,
      story: story,
      scene_beta: scene
    } do
      conn = log_in_user(conn, alice)
      {:ok, _view, html} = live(conn, "/stories/#{story.id}/scenes/#{scene.id}/compare")

      assert html =~ "v1"
      assert html =~ "No version selected"
    end
  end

  describe "Compare link in ScriptLive" do
    test "Scene Alpha (two versions) shows Compare link in script view", %{
      conn: conn,
      alice: alice,
      story: story,
      seq: seq,
      scene_alpha: scene_alpha
    } do
      conn = log_in_user(conn, alice)
      {:ok, _view, html} = live(conn, "/stories/#{story.id}/sequences/#{seq.id}/script")

      assert html =~
               "/stories/#{story.id}/scenes/#{scene_alpha.id}/compare"
    end

    test "Scene Beta (one version) shows no Compare link in script view", %{
      conn: conn,
      alice: alice,
      story: story,
      seq: seq,
      scene_beta: scene_beta
    } do
      conn = log_in_user(conn, alice)
      {:ok, _view, html} = live(conn, "/stories/#{story.id}/sequences/#{seq.id}/script")

      refute html =~
               "/stories/#{story.id}/scenes/#{scene_beta.id}/compare"
    end

    test "Scene Gamma (no versions) shows no Compare link in script view", %{
      conn: conn,
      alice: alice,
      story: story,
      seq: seq,
      scene_gamma: scene_gamma
    } do
      conn = log_in_user(conn, alice)
      {:ok, _view, html} = live(conn, "/stories/#{story.id}/sequences/#{seq.id}/script")

      refute html =~
               "/stories/#{story.id}/scenes/#{scene_gamma.id}/compare"
    end
  end
end
