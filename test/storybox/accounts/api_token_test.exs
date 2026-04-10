defmodule Storybox.Accounts.ApiTokenTest do
  use Storybox.DataCase

  alias Storybox.Accounts.ApiToken

  setup do
    {:ok, user} =
      Storybox.Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "api_test@example.com",
        password: "password123!",
        password_confirmation: "password123!"
      })
      |> Ash.create()

    {:ok, story} =
      Storybox.Stories.Story
      |> Ash.Changeset.for_create(:create, %{title: "Test Story", user_id: user.id})
      |> Ash.create()

    %{user: user, story: story}
  end

  describe "generate/1" do
    test "returns a raw token and a persisted record", %{user: user, story: story} do
      assert {:ok, raw_token, record} =
               ApiToken.generate(%{story_id: story.id, user_id: user.id, label: "agent-1"})

      assert is_binary(raw_token)
      assert String.length(raw_token) > 0
      assert record.story_id == story.id
      assert record.user_id == user.id
      assert record.label == "agent-1"
      refute record.token_hash == raw_token
    end

    test "raw token differs between two generate calls", %{user: user, story: story} do
      {:ok, token1, _} = ApiToken.generate(%{story_id: story.id, user_id: user.id})
      {:ok, token2, _} = ApiToken.generate(%{story_id: story.id, user_id: user.id})
      refute token1 == token2
    end
  end

  describe "verify/1" do
    test "succeeds with a valid token", %{user: user, story: story} do
      {:ok, raw_token, record} = ApiToken.generate(%{story_id: story.id, user_id: user.id})

      assert {:ok, verified} = ApiToken.verify(raw_token)
      assert verified.id == record.id
      assert verified.story_id == story.id
    end

    test "returns :not_found for an unknown token" do
      assert {:error, :not_found} = ApiToken.verify("notavalidtoken")
    end

    test "returns :not_found for a garbage token" do
      assert {:error, :not_found} = ApiToken.verify("")
    end

    test "returns :expired for an expired token", %{user: user, story: story} do
      past = DateTime.add(DateTime.utc_now(), -3600, :second)

      {:ok, raw_token, _} =
        ApiToken.generate(%{story_id: story.id, user_id: user.id, expires_at: past})

      assert {:error, :expired} = ApiToken.verify(raw_token)
    end

    test "succeeds for a token that has not yet expired", %{user: user, story: story} do
      future = DateTime.add(DateTime.utc_now(), 3600, :second)

      {:ok, raw_token, _} =
        ApiToken.generate(%{story_id: story.id, user_id: user.id, expires_at: future})

      assert {:ok, _} = ApiToken.verify(raw_token)
    end
  end
end
