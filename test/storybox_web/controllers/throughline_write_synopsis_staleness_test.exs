defmodule StoryboxWeb.ThroughlineWriteSynopsisStalenessTest do
  @moduledoc """
  The seam between the nested through-line write path and the synopsis
  staleness cascade.

  Every harness mutation here goes through `POST
  /api/stories/:story_id/throughline/pieces` — the nested bottom-up cut — rather
  than constructing a `ThroughlineViewVersion` directly. That is the point: the
  existing cascade tests cut the top view by hand and the existing write-path
  tests stop at the cut, so a dropped cascade call in the nested path would
  surface as nothing happening.
  """
  use StoryboxWeb.ConnCase

  require Ash.Query

  alias Storybox.Accounts.ApiToken
  alias Storybox.Stories.{Staleness, SynopsisView, SynopsisViewVersion, Task}

  setup do
    {:ok, user} =
      Storybox.Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "throughline_write_synopsis_staleness_test@example.com",
        password: "password123!",
        password_confirmation: "password123!"
      })
      |> Ash.create()

    {:ok, story} =
      Storybox.Stories.Story
      |> Ash.Changeset.for_create(:create, %{title: "Staleness Seam Story", user_id: user.id})
      |> Ash.create()

    {:ok, char} =
      Storybox.Stories.Character
      |> Ash.Changeset.for_create(:create, %{story_id: story.id, name: "Alice"})
      |> Ash.create(authorize?: false)

    {:ok, raw_token, _} = ApiToken.generate(%{story_id: story.id, user_id: user.id})

    {:ok, synopsis_view} =
      SynopsisView
      |> Ash.ActionInput.for_action(:ensure_for_story, %{story_id: story.id})
      |> Ash.run_action()

    %{story: story, char: char, raw_token: raw_token, synopsis_view: synopsis_view}
  end

  defp authed(conn, raw_token) do
    put_req_header(conn, "authorization", "Bearer #{raw_token}")
  end

  # A through-line write through the HTTP endpoint. `character_id` nil is a
  # story-arc write (controlling idea); otherwise it is a character-arc write.
  defp write_throughline(
         %{conn: conn, story: story, raw_token: token},
         content,
         character_id \\ nil
       ) do
    body =
      %{"content" => content}
      |> then(fn b -> if character_id, do: Map.put(b, "character_id", character_id), else: b end)

    conn
    |> authed(token)
    |> post("/api/stories/#{story.id}/throughline/pieces", body)
    |> json_response(201)
  end

  defp cut_synopsis_vv(synopsis_view_id) do
    {:ok, svv} =
      SynopsisViewVersion
      |> Ash.ActionInput.for_action(:cut, %{synopsis_view_id: synopsis_view_id})
      |> Ash.run_action()

    svv
  end

  defp review_tasks_for(vv_id) do
    Task
    |> Ash.Query.filter(target_view_version_id == ^vv_id and type == :review)
    |> Ash.read!(authorize?: false)
  end

  describe "nested through-line write to synopsis staleness cascade" do
    test "a character-arc write makes a previously-current synopsis version harness-stale", ctx do
      %{synopsis_view: synopsis_view, char: char} = ctx

      # Establish the harness through the write path, then cut a synopsis
      # version against it — it records the top VV that write produced.
      write_throughline(ctx, "Alice v1.", char.id)
      svv = cut_synopsis_vv(synopsis_view.id)

      refute Staleness.view_version_stale?(svv.id, :synopsis_vv)

      # A second character write re-cuts character → cast → top.
      write_throughline(ctx, "Alice v2.", char.id)

      assert Staleness.view_version_stale?(svv.id, :synopsis_vv)
    end

    test "that write generates one :review task, and a repeat write does not duplicate it", ctx do
      %{story: story, synopsis_view: synopsis_view, char: char} = ctx

      write_throughline(ctx, "Alice v1.", char.id)
      svv = cut_synopsis_vv(synopsis_view.id)

      assert review_tasks_for(svv.id) == []

      write_throughline(ctx, "Alice v2.", char.id)

      [task] = review_tasks_for(svv.id)
      assert task.target_view_version_id == svv.id
      assert task.target_view_type == "synopsis_vv"
      assert task.component_type == :story
      assert task.component_id == story.id
      assert task.triggered_by_piece_type == "throughline_vv"

      # A third write against the same character advances the harness again, but
      # the pending review task for this synopsis version is already open.
      write_throughline(ctx, "Alice v3.", char.id)

      assert length(review_tasks_for(svv.id)) == 1
    end

    test "a story-arc write produces the same staleness result, cast pin notwithstanding", ctx do
      %{synopsis_view: synopsis_view, char: char} = ctx

      # A character write first, so the top view carries a cast pin that the
      # story-arc write will carry forward untouched.
      write_throughline(ctx, "Alice v1.", char.id)
      svv = cut_synopsis_vv(synopsis_view.id)

      refute Staleness.view_version_stale?(svv.id, :synopsis_vv)

      write_throughline(ctx, "The cost of revenge.")

      assert Staleness.view_version_stale?(svv.id, :synopsis_vv)
    end

    test "cut against the current top version reads clean, then stale after a character write",
         ctx do
      %{synopsis_view: synopsis_view, char: char} = ctx

      write_throughline(ctx, "The cost of revenge.")
      write_throughline(ctx, "Alice v1.", char.id)

      svv = cut_synopsis_vv(synopsis_view.id)
      refute Staleness.view_version_stale?(svv.id, :synopsis_vv)

      write_throughline(ctx, "Alice v2.", char.id)

      assert Staleness.view_version_stale?(svv.id, :synopsis_vv)
    end

    test "cut against the current top version reads clean, then stale after a story write", ctx do
      %{synopsis_view: synopsis_view, char: char} = ctx

      write_throughline(ctx, "The cost of revenge.")
      write_throughline(ctx, "Alice v1.", char.id)

      svv = cut_synopsis_vv(synopsis_view.id)
      refute Staleness.view_version_stale?(svv.id, :synopsis_vv)

      write_throughline(ctx, "The price of mercy.")

      assert Staleness.view_version_stale?(svv.id, :synopsis_vv)
    end

    test "a harness with no cast pinned neither crashes nor reports false staleness", ctx do
      %{story: story, synopsis_view: synopsis_view} = ctx

      # Story-arc writes only — no CharacterThroughlineView or ThroughlineCastView
      # is ever created, so the top view's cast slot stays empty throughout.
      write_throughline(ctx, "The cost of revenge.")

      assert is_nil(
               Storybox.Stories.ThroughlineCastView
               |> Ash.Query.filter(story_id == ^story.id)
               |> Ash.read_one!(authorize?: false)
             )

      svv = cut_synopsis_vv(synopsis_view.id)
      refute Staleness.view_version_stale?(svv.id, :synopsis_vv)

      write_throughline(ctx, "The price of mercy.")

      assert Staleness.view_version_stale?(svv.id, :synopsis_vv)
    end
  end
end
