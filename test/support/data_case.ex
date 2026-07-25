defmodule Storybox.DataCase do
  @moduledoc """
  This module defines the setup for tests requiring
  access to the application's data layer.

  You may define functions here to be used as helpers in
  your tests.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use Storybox.DataCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      alias Storybox.Repo

      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import Storybox.DataCase
    end
  end

  setup tags do
    Storybox.DataCase.setup_sandbox(tags)
    :ok
  end

  @doc """
  Sets up the sandbox based on the test tags.
  """
  def setup_sandbox(tags) do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(Storybox.Repo, shared: not tags[:async])
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
  end

  @doc """
  Places a Sequence on its Story's spine at the tail, creating the spine if
  absent. Sequences are created off-spine, so tests that need a sequence in the
  running order (any cut, view-read, or spine-entry assertion) place it here.
  """
  def place_on_spine(story_id, sequence_id) do
    {:ok, spine} =
      Storybox.Stories.StorySpine
      |> Ash.ActionInput.for_action(:ensure_for_story, %{story_id: story_id})
      |> Ash.run_action(authorize?: false)

    Storybox.Stories.StorySpine
    |> Ash.ActionInput.for_action(:add_entry, %{
      story_spine_id: spine.id,
      sequence_id: sequence_id
    })
    |> Ash.run_action!(authorize?: false)
  end

  @doc """
  A helper that transforms changeset errors into a map of messages.

      assert {:error, changeset} = Accounts.create_user(%{password: "short"})
      assert "password is too short" in errors_on(changeset).password
      assert %{password: ["password is too short"]} = errors_on(changeset)

  """
  def errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
