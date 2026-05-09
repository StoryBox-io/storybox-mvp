defmodule StoryboxWeb.TaskApiTest do
  use StoryboxWeb.ConnCase

  alias Storybox.Accounts.ApiToken
  alias Storybox.Stories.{SynopsisView, Task}

  require Ash.Query

  # Setup creates:
  #   user_a ──── story_a ──── synopsis_view_a ──── task_a (pending)
  #   user_a ──── story_b ──── synopsis_view_b ──── task_b (pending)
  #
  # token_a is scoped to story_a; token_b is scoped to story_b.

  setup do
    {:ok, user_a} =
      Storybox.Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "task_api_a@example.com",
        password: "password123!",
        password_confirmation: "password123!"
      })
      |> Ash.create()

    {:ok, story_a} =
      Storybox.Stories.Story
      |> Ash.Changeset.for_create(:create, %{title: "Story A", user_id: user_a.id})
      |> Ash.create()

    {:ok, story_b} =
      Storybox.Stories.Story
      |> Ash.Changeset.for_create(:create, %{title: "Story B", user_id: user_a.id})
      |> Ash.create()

    {:ok, raw_token_a, _} = ApiToken.generate(%{story_id: story_a.id, user_id: user_a.id})
    {:ok, raw_token_b, _} = ApiToken.generate(%{story_id: story_b.id, user_id: user_a.id})

    {:ok, view_a} =
      SynopsisView
      |> Ash.ActionInput.for_action(:ensure_for_story, %{story_id: story_a.id})
      |> Ash.run_action(authorize?: false)

    {:ok, view_b} =
      SynopsisView
      |> Ash.ActionInput.for_action(:ensure_for_story, %{story_id: story_b.id})
      |> Ash.run_action(authorize?: false)

    {:ok, task_a} =
      Task
      |> Ash.Changeset.for_create(:create, %{
        story_id: story_a.id,
        component_type: :story,
        component_id: story_a.id,
        target_view_id: view_a.id,
        target_view_type: "synopsis_vv",
        type: :creation,
        status: :pending
      })
      |> Ash.create(authorize?: false)

    {:ok, task_b} =
      Task
      |> Ash.Changeset.for_create(:create, %{
        story_id: story_b.id,
        component_type: :story,
        component_id: story_b.id,
        target_view_id: view_b.id,
        target_view_type: "synopsis_vv",
        type: :creation,
        status: :pending
      })
      |> Ash.create(authorize?: false)

    %{
      story_a: story_a,
      story_b: story_b,
      task_a: task_a,
      task_b: task_b,
      raw_token_a: raw_token_a,
      raw_token_b: raw_token_b
    }
  end

  describe "GET /api/stories/:story_id/tasks" do
    test "returns 200 with JSON array of tasks", %{
      conn: conn,
      story_a: story_a,
      raw_token_a: token
    } do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> get("/api/stories/#{story_a.id}/tasks?status=pending")

      body = json_response(conn, 200)
      assert is_list(body)
    end

    test "returns tasks scoped to the authenticated story only", %{
      conn: conn,
      story_a: story_a,
      task_a: task_a,
      task_b: task_b,
      raw_token_a: token
    } do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> get("/api/stories/#{story_a.id}/tasks?status=pending")

      body = json_response(conn, 200)
      ids = Enum.map(body, & &1["id"])
      assert task_a.id in ids
      refute task_b.id in ids
    end

    test "filters by component_id", %{
      conn: conn,
      story_a: story_a,
      task_a: task_a,
      raw_token_a: token
    } do
      other_id = Ecto.UUID.generate()

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> get("/api/stories/#{story_a.id}/tasks?status=pending&component_id=#{other_id}")

      body = json_response(conn, 200)
      ids = Enum.map(body, & &1["id"])
      refute task_a.id in ids
    end

    test "returns 400 for invalid status", %{
      conn: conn,
      story_a: story_a,
      raw_token_a: token
    } do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> get("/api/stories/#{story_a.id}/tasks?status=banana")

      assert json_response(conn, 400)["error"] =~ "status"
    end

    test "returns 401 without a token", %{conn: conn, story_a: story_a} do
      conn = get(conn, "/api/stories/#{story_a.id}/tasks?status=pending")
      assert json_response(conn, 401)
    end

    test "returns 403 when token story does not match path story_id", %{
      conn: conn,
      story_a: story_a,
      raw_token_b: token_b
    } do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token_b}")
        |> get("/api/stories/#{story_a.id}/tasks?status=pending")

      assert json_response(conn, 403)
    end
  end

  describe "POST /api/stories/:story_id/tasks/:id/in_progress" do
    test "returns 200 with updated task JSON", %{
      conn: conn,
      story_a: story_a,
      task_a: task_a,
      raw_token_a: token
    } do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> post("/api/stories/#{story_a.id}/tasks/#{task_a.id}/in_progress")

      body = json_response(conn, 200)
      assert body["id"] == task_a.id
      assert body["status"] == "in_progress"
    end

    test "returns 404 for a non-existent task id", %{
      conn: conn,
      story_a: story_a,
      raw_token_a: token
    } do
      fake_id = "00000000-0000-0000-0000-000000000000"

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> post("/api/stories/#{story_a.id}/tasks/#{fake_id}/in_progress")

      assert json_response(conn, 404)["error"] == "not found"
    end

    test "returns 403 when token scoped to story B tries to update story A task", %{
      conn: conn,
      story_a: story_a,
      task_a: task_a,
      raw_token_b: token_b
    } do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token_b}")
        |> post("/api/stories/#{story_a.id}/tasks/#{task_a.id}/in_progress")

      # Auth plug rejects because token.story_id != path story_id
      assert json_response(conn, 403)
    end
  end

  describe "POST /api/stories/:story_id/tasks/:id/complete" do
    test "returns 200 with task JSON with status complete", %{
      conn: conn,
      story_a: story_a,
      raw_token_a: token
    } do
      {:ok, in_progress_task} =
        Task
        |> Ash.Changeset.for_create(:create, %{
          story_id: story_a.id,
          component_type: :story,
          component_id: story_a.id,
          target_view_id: story_a.id,
          target_view_type: "synopsis_vv",
          type: :refinement,
          status: :in_progress
        })
        |> Ash.create(authorize?: false)

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> post("/api/stories/#{story_a.id}/tasks/#{in_progress_task.id}/complete")

      body = json_response(conn, 200)
      assert body["id"] == in_progress_task.id
      assert body["status"] == "complete"
    end

    test "returns 404 for a non-existent task id", %{
      conn: conn,
      story_a: story_a,
      raw_token_a: token
    } do
      fake_id = "00000000-0000-0000-0000-000000000000"

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> post("/api/stories/#{story_a.id}/tasks/#{fake_id}/complete")

      assert json_response(conn, 404)["error"] == "not found"
    end
  end
end
