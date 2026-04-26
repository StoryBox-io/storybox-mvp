defmodule StoryboxWeb.ScriptLiveTest do
  use StoryboxWeb.ConnCase

  import Phoenix.LiveViewTest

  require Ash.Query

  # Seed data graph:
  #
  #   alice ──► "The Illusionist"  (through_lines: ["preference"])
  #               └── TreatmentView "Act 1"  pos 1
  #                     ├── ScriptView "Opening"  pos 1  approved → nil
  #                     │     ├── sp_v1  weights: {}      status: current
  #                     │     └── sp_v2  weights: {}      status: current
  #                     └── ScriptView "Confrontation"  pos 2  approved → sp_v1
  #                           └── sp_v1  weights: {preference→0.9}  status: current  [approved]

  setup do
    {:ok, alice} =
      Storybox.Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "alice@example.com",
        password: "password123!",
        password_confirmation: "password123!"
      })
      |> Ash.create()

    {:ok, story} =
      Storybox.Stories.Story
      |> Ash.Changeset.for_create(:create, %{
        title: "The Illusionist",
        through_lines: ["preference"],
        user_id: alice.id
      })
      |> Ash.create()

    {:ok, treatment_view} =
      Storybox.Stories.TreatmentView
      |> Ash.Changeset.for_create(:create, %{
        title: "Act 1",
        position: 1,
        story_id: story.id
      })
      |> Ash.create()

    # ScriptView "Opening" — two versions, no approved
    {:ok, sv_opening} =
      Storybox.Stories.ScriptView
      |> Ash.Changeset.for_create(:create, %{
        title: "Opening",
        position: 1,
        treatment_view_id: treatment_view.id
      })
      |> Ash.create()

    {:ok, opening_v1} =
      Storybox.Stories.ScriptPiece
      |> Ash.Changeset.for_create(:create, %{
        script_view_id: sv_opening.id,
        content_uri: "storybox://test/opening/v1",
        version_number: 1,
        upstream_status: :current,
        weights: %{}
      })
      |> Ash.create()

    {:ok, opening_v2} =
      Storybox.Stories.ScriptPiece
      |> Ash.Changeset.for_create(:create, %{
        script_view_id: sv_opening.id,
        content_uri: "storybox://test/opening/v2",
        version_number: 2,
        upstream_status: :current,
        weights: %{}
      })
      |> Ash.create()

    # ScriptView "Confrontation" — one version, approved, already reviewed
    {:ok, sv_confrontation} =
      Storybox.Stories.ScriptView
      |> Ash.Changeset.for_create(:create, %{
        title: "Confrontation",
        position: 2,
        treatment_view_id: treatment_view.id
      })
      |> Ash.create()

    {:ok, confrontation_v1} =
      Storybox.Stories.ScriptPiece
      |> Ash.Changeset.for_create(:create, %{
        script_view_id: sv_confrontation.id,
        content_uri: "storybox://test/confrontation/v1",
        version_number: 1,
        upstream_status: :current,
        weights: %{"preference" => 0.9}
      })
      |> Ash.create()

    {:ok, sv_confrontation} =
      sv_confrontation
      |> Ash.Changeset.for_update(:approve_version, %{version_id: confrontation_v1.id})
      |> Ash.update()

    %{
      alice: alice,
      story: story,
      treatment_view: treatment_view,
      sv_opening: sv_opening,
      opening_v1: opening_v1,
      opening_v2: opening_v2,
      sv_confrontation: sv_confrontation,
      confrontation_v1: confrontation_v1
    }
  end

  describe "weight form" do
    test "unreviewed version row has the ring-warning indicator", %{
      conn: conn,
      alice: alice,
      story: story,
      treatment_view: treatment_view
    } do
      conn = log_in_user(conn, alice)

      {:ok, _view, html} =
        live(conn, "/stories/#{story.id}/sequences/#{treatment_view.id}/script")

      assert html =~ "ring-warning"
    end

    test "clicking Review on Opening v2 (latest) renders a range input for each through_line", %{
      conn: conn,
      alice: alice,
      story: story,
      treatment_view: treatment_view,
      opening_v2: opening_v2
    } do
      conn = log_in_user(conn, alice)

      {:ok, view, _html} =
        live(conn, "/stories/#{story.id}/sequences/#{treatment_view.id}/script")

      html =
        view
        |> element(
          "[phx-click=\"toggle_weight_form\"][phx-value-version-id=\"#{opening_v2.id}\"]",
          "Review"
        )
        |> render_click()

      assert html =~ ~s(name="weights[preference]")
    end

    test "submitting the weight form persists weights and updates the badge", %{
      conn: conn,
      alice: alice,
      story: story,
      treatment_view: treatment_view,
      opening_v2: opening_v2
    } do
      conn = log_in_user(conn, alice)

      {:ok, view, _html} =
        live(conn, "/stories/#{story.id}/sequences/#{treatment_view.id}/script")

      # Open the form on the latest version (v2)
      view
      |> element(
        "[phx-click=\"toggle_weight_form\"][phx-value-version-id=\"#{opening_v2.id}\"]",
        "Review"
      )
      |> render_click()

      # Submit weights
      view
      |> form("form[phx-submit=\"set_weights\"]",
        version_id: opening_v2.id,
        weights: %{"preference" => "0.75"}
      )
      |> render_submit()

      # Persisted in DB
      updated =
        Storybox.Stories.ScriptPiece
        |> Ash.Query.filter(id == ^opening_v2.id)
        |> Ash.read_one!(authorize?: false)

      assert updated.weights == %{"preference" => 0.75}

      # Badge shows reviewed
      html = render(view)
      assert html =~ "reviewed"
    end
  end
end
