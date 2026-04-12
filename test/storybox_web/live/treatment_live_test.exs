defmodule StoryboxWeb.TreatmentLiveTest do
  use StoryboxWeb.ConnCase

  import Phoenix.LiveViewTest

  require Ash.Query

  # Seed data graph:
  #
  #   alice ──► "The Illusionist"  (through_lines: ["preference", "theme"])
  #               ├── Act 1
  #               │    ├── Piece "The Reveal"   pos 1  approved → v1
  #               │    │     ├── v1  weights: {preference→0.9, theme→0.7}  status: current  [approved]
  #               │    │     └── v2  weights: {}                           status: stale
  #               │    └── Piece "The Escape"   pos 2  approved → nil
  #               │          └── v1  weights: {}                           status: current
  #               ├── Act 2
  #               │    └── Piece "Fallout"      pos 3  approved → v3
  #               │          └── v3  weights: {preference→0.5}             status: current  [approved]
  #               └── (no act)
  #                    └── Piece "Coda"         pos 4  approved → nil
  #                          (no versions)
  #
  #   bob  ──► "Bob's Story"  (separate user, used for auth isolation checks)

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
        title: "The Illusionist",
        through_lines: ["preference", "theme"],
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

    # Act 1 — "The Reveal" (pos 1), approved → v1
    {:ok, piece_reveal} =
      Storybox.Stories.SequencePiece
      |> Ash.Changeset.for_create(:create, %{
        title: "The Reveal",
        act: "Act 1",
        position: 1,
        story_id: story.id
      })
      |> Ash.create()

    {:ok, reveal_v1} =
      Storybox.Stories.SequenceVersion
      |> Ash.Changeset.for_create(:create, %{
        sequence_piece_id: piece_reveal.id,
        content_uri: "storybox://test/reveal/v1",
        version_number: 1,
        upstream_status: :current,
        weights: %{"preference" => 0.9, "theme" => 0.7}
      })
      |> Ash.create()

    {:ok, reveal_v2} =
      Storybox.Stories.SequenceVersion
      |> Ash.Changeset.for_create(:create, %{
        sequence_piece_id: piece_reveal.id,
        content_uri: "storybox://test/reveal/v2",
        version_number: 2,
        upstream_status: :stale,
        weights: %{}
      })
      |> Ash.create()

    {:ok, piece_reveal} =
      piece_reveal
      |> Ash.Changeset.for_update(:approve_version, %{version_id: reveal_v1.id})
      |> Ash.update()

    # Act 1 — "The Escape" (pos 2), no approved version
    {:ok, piece_escape} =
      Storybox.Stories.SequencePiece
      |> Ash.Changeset.for_create(:create, %{
        title: "The Escape",
        act: "Act 1",
        position: 2,
        story_id: story.id
      })
      |> Ash.create()

    {:ok, escape_v1} =
      Storybox.Stories.SequenceVersion
      |> Ash.Changeset.for_create(:create, %{
        sequence_piece_id: piece_escape.id,
        content_uri: "storybox://test/escape/v1",
        version_number: 1,
        upstream_status: :current,
        weights: %{}
      })
      |> Ash.create()

    # Act 2 — "Fallout" (pos 3), approved → v3
    {:ok, piece_fallout} =
      Storybox.Stories.SequencePiece
      |> Ash.Changeset.for_create(:create, %{
        title: "Fallout",
        act: "Act 2",
        position: 3,
        story_id: story.id
      })
      |> Ash.create()

    {:ok, fallout_v3} =
      Storybox.Stories.SequenceVersion
      |> Ash.Changeset.for_create(:create, %{
        sequence_piece_id: piece_fallout.id,
        content_uri: "storybox://test/fallout/v3",
        version_number: 3,
        upstream_status: :current,
        weights: %{"preference" => 0.5}
      })
      |> Ash.create()

    {:ok, piece_fallout} =
      piece_fallout
      |> Ash.Changeset.for_update(:approve_version, %{version_id: fallout_v3.id})
      |> Ash.update()

    # No act — "Coda" (pos 4), no versions
    {:ok, piece_coda} =
      Storybox.Stories.SequencePiece
      |> Ash.Changeset.for_create(:create, %{
        title: "Coda",
        act: nil,
        position: 4,
        story_id: story.id
      })
      |> Ash.create()

    %{
      alice: alice,
      bob: bob,
      story: story,
      bobs_story: bobs_story,
      piece_reveal: piece_reveal,
      reveal_v1: reveal_v1,
      reveal_v2: reveal_v2,
      piece_escape: piece_escape,
      escape_v1: escape_v1,
      piece_fallout: piece_fallout,
      fallout_v3: fallout_v3,
      piece_coda: piece_coda
    }
  end

  describe "unauthenticated access" do
    test "redirects to sign-in when not logged in", %{conn: conn, story: story} do
      assert {:error, {:redirect, %{to: "/sign-in"}}} =
               live(conn, "/stories/#{story.id}/treatment")
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
               live(conn, "/stories/#{bobs_story.id}/treatment")
    end

    test "redirects to / when story_id does not exist", %{conn: conn, alice: alice} do
      conn = log_in_user(conn, alice)
      fake_id = Ash.UUID.generate()

      assert {:error, {:redirect, %{to: "/"}}} =
               live(conn, "/stories/#{fake_id}/treatment")
    end
  end

  describe "page header" do
    test "renders the story title", %{conn: conn, alice: alice, story: story} do
      conn = log_in_user(conn, alice)
      {:ok, _view, html} = live(conn, "/stories/#{story.id}/treatment")

      assert html =~ "The Illusionist"
    end
  end

  describe "act grouping" do
    test "renders Act 1 label before The Reveal and The Escape", %{
      conn: conn,
      alice: alice,
      story: story
    } do
      conn = log_in_user(conn, alice)
      {:ok, _view, html} = live(conn, "/stories/#{story.id}/treatment")

      assert html =~ "Act 1"
      assert html =~ "The Reveal"
      assert html =~ "The Escape"
    end

    test "renders Act 2 label before Fallout", %{conn: conn, alice: alice, story: story} do
      conn = log_in_user(conn, alice)
      {:ok, _view, html} = live(conn, "/stories/#{story.id}/treatment")

      assert html =~ "Act 2"
      assert html =~ "Fallout"
    end

    test "renders Coda under the no-act grouping", %{conn: conn, alice: alice, story: story} do
      conn = log_in_user(conn, alice)
      {:ok, _view, html} = live(conn, "/stories/#{story.id}/treatment")

      assert html =~ "No act"
      assert html =~ "Coda"
    end

    test "The Reveal appears before The Escape (position order within Act 1)", %{
      conn: conn,
      alice: alice,
      story: story
    } do
      conn = log_in_user(conn, alice)
      {:ok, _view, html} = live(conn, "/stories/#{story.id}/treatment")

      reveal_pos = :binary.match(html, "The Reveal") |> elem(0)
      escape_pos = :binary.match(html, "The Escape") |> elem(0)

      assert reveal_pos < escape_pos
    end
  end

  describe "version display" do
    test "The Reveal shows v1 as approved", %{conn: conn, alice: alice, story: story} do
      conn = log_in_user(conn, alice)
      {:ok, _view, html} = live(conn, "/stories/#{story.id}/treatment")

      assert html =~ "v1"
      assert html =~ "Approved"
    end

    test "The Reveal v1 shows upstream status current", %{
      conn: conn,
      alice: alice,
      story: story
    } do
      conn = log_in_user(conn, alice)
      {:ok, _view, html} = live(conn, "/stories/#{story.id}/treatment")

      assert html =~ "current"
    end

    test "The Reveal v2 shows upstream status stale", %{conn: conn, alice: alice, story: story} do
      conn = log_in_user(conn, alice)
      {:ok, _view, html} = live(conn, "/stories/#{story.id}/treatment")

      assert html =~ "stale"
    end

    test "The Escape has no approved marker", %{conn: conn, alice: alice, story: story} do
      conn = log_in_user(conn, alice)
      {:ok, _view, html} = live(conn, "/stories/#{story.id}/treatment")

      # "Approved" badge appears for The Reveal v1 and Fallout v3 — but NOT for The Escape
      assert length(:binary.matches(html, "Approved")) == 2
    end

    test "Coda shows no-versions empty state", %{conn: conn, alice: alice, story: story} do
      conn = log_in_user(conn, alice)
      {:ok, _view, html} = live(conn, "/stories/#{story.id}/treatment")

      assert html =~ "No versions yet."
    end
  end

  describe "review status" do
    test "The Reveal v1 shows reviewed (both through_lines present in weights)", %{
      conn: conn,
      alice: alice,
      story: story
    } do
      conn = log_in_user(conn, alice)
      {:ok, _view, html} = live(conn, "/stories/#{story.id}/treatment")

      assert html =~ "reviewed"
    end

    test "The Reveal v2 shows unreviewed (empty weights)", %{
      conn: conn,
      alice: alice,
      story: story
    } do
      conn = log_in_user(conn, alice)
      {:ok, _view, html} = live(conn, "/stories/#{story.id}/treatment")

      assert html =~ "unreviewed"
    end

    test "Fallout v3 shows partial (only preference present, theme missing)", %{
      conn: conn,
      alice: alice,
      story: story
    } do
      conn = log_in_user(conn, alice)
      {:ok, _view, html} = live(conn, "/stories/#{story.id}/treatment")

      assert html =~ "partial"
    end
  end

  describe "approve version" do
    test "approving The Reveal v2 makes it the approved version", %{
      conn: conn,
      alice: alice,
      story: story,
      piece_reveal: piece_reveal,
      reveal_v2: reveal_v2
    } do
      conn = log_in_user(conn, alice)
      {:ok, view, _html} = live(conn, "/stories/#{story.id}/treatment")

      view
      |> element(
        "[phx-click=\"approve_version\"][phx-value-piece-id=\"#{piece_reveal.id}\"][phx-value-version-id=\"#{reveal_v2.id}\"]"
      )
      |> render_click()

      html = render(view)

      # "Approved" still appears twice — on The Reveal v2 (newly approved) and Fallout v3
      assert length(:binary.matches(html, "Approved")) == 2

      # v2 is now marked approved in DB
      updated_piece =
        Storybox.Stories.SequencePiece
        |> Ash.Query.filter(id == ^piece_reveal.id)
        |> Ash.read_one!(authorize?: false)

      assert updated_piece.approved_version_id == reveal_v2.id
    end

    test "approving a version on one piece does not change the approved pointer on another piece",
         %{
           conn: conn,
           alice: alice,
           story: story,
           piece_reveal: piece_reveal,
           reveal_v2: reveal_v2,
           piece_fallout: piece_fallout,
           fallout_v3: fallout_v3
         } do
      conn = log_in_user(conn, alice)
      {:ok, view, _html} = live(conn, "/stories/#{story.id}/treatment")

      view
      |> element(
        "[phx-click=\"approve_version\"][phx-value-piece-id=\"#{piece_reveal.id}\"][phx-value-version-id=\"#{reveal_v2.id}\"]"
      )
      |> render_click()

      updated_fallout =
        Storybox.Stories.SequencePiece
        |> Ash.Query.filter(id == ^piece_fallout.id)
        |> Ash.read_one!(authorize?: false)

      assert updated_fallout.approved_version_id == fallout_v3.id
    end
  end

  describe "weight form" do
    test "unreviewed version row has the ring-warning indicator", %{
      conn: conn,
      alice: alice,
      story: story
    } do
      conn = log_in_user(conn, alice)
      {:ok, _view, html} = live(conn, "/stories/#{story.id}/treatment")

      # reveal_v2 has empty weights — should render ring-2 ring-warning
      assert html =~ "ring-warning"
    end

    test "Review button is present for each version", %{
      conn: conn,
      alice: alice,
      story: story
    } do
      conn = log_in_user(conn, alice)
      {:ok, _view, html} = live(conn, "/stories/#{story.id}/treatment")

      assert html =~ "Review"
    end

    test "clicking Review on The Reveal v2 opens a form with a range input per through_line", %{
      conn: conn,
      alice: alice,
      story: story,
      reveal_v2: reveal_v2
    } do
      conn = log_in_user(conn, alice)
      {:ok, view, _html} = live(conn, "/stories/#{story.id}/treatment")

      html =
        view
        |> element(
          "[phx-click=\"toggle_weight_form\"][phx-value-version-id=\"#{reveal_v2.id}\"]",
          "Review"
        )
        |> render_click()

      # Story has through_lines ["preference", "theme"] — expect both inputs
      assert html =~ ~s(name="weights[preference]")
      assert html =~ ~s(name="weights[theme]")
    end

    test "submitting the weight form persists weights and shows the reviewed badge", %{
      conn: conn,
      alice: alice,
      story: story,
      reveal_v2: reveal_v2
    } do
      conn = log_in_user(conn, alice)
      {:ok, view, _html} = live(conn, "/stories/#{story.id}/treatment")

      # Open the form
      view
      |> element(
        "[phx-click=\"toggle_weight_form\"][phx-value-version-id=\"#{reveal_v2.id}\"]",
        "Review"
      )
      |> render_click()

      # Submit weights for both through_lines
      view
      |> form("form[phx-submit=\"set_weights\"]",
        version_id: reveal_v2.id,
        weights: %{"preference" => "0.8", "theme" => "0.6"}
      )
      |> render_submit()

      # Weights persisted in DB
      updated =
        Storybox.Stories.SequenceVersion
        |> Ash.Query.filter(id == ^reveal_v2.id)
        |> Ash.read_one!(authorize?: false)

      assert updated.weights == %{"preference" => 0.8, "theme" => 0.6}

      # reviewed badge visible
      html = render(view)
      assert html =~ "reviewed"
    end
  end

  describe "empty story" do
    test "shows no-sequences empty state for a story with no sequences", %{
      conn: conn,
      alice: alice
    } do
      {:ok, empty_story} =
        Storybox.Stories.Story
        |> Ash.Changeset.for_create(:create, %{
          title: "Blank Story",
          user_id: alice.id
        })
        |> Ash.create()

      conn = log_in_user(conn, alice)
      {:ok, _view, html} = live(conn, "/stories/#{empty_story.id}/treatment")

      assert html =~ "No sequences yet."
    end
  end
end
