defmodule Storybox.Stories.WorldViewVersionTest do
  use Storybox.DataCase

  require Ash.Query

  setup do
    {:ok, user} =
      Storybox.Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "wvv_test@example.com",
        password: "password123!",
        password_confirmation: "password123!"
      })
      |> Ash.create()

    {:ok, story} =
      Storybox.Stories.Story
      |> Ash.Changeset.for_create(:create, %{title: "Test Story", user_id: user.id})
      |> Ash.create()

    {:ok, world} =
      Storybox.Stories.World
      |> Ash.Changeset.for_create(:create, %{name: "External World", story_id: story.id})
      |> Ash.create()

    {:ok, piece} =
      Storybox.Stories.WorldPiece
      |> Ash.ActionInput.for_action(:create_version, %{
        world_id: world.id,
        content: "History: Ancient.\n\nRules: Magic costs.\n\nSubtext: Power corrupts."
      })
      |> Ash.run_action()

    {:ok, world_view} =
      Storybox.Stories.WorldView
      |> Ash.ActionInput.for_action(:ensure_for_world, %{world_id: world.id})
      |> Ash.run_action()

    %{world_view: world_view, piece: piece}
  end

  describe "cut" do
    test "creates a WorldViewVersion with version_number 1 on first call", %{
      world_view: wv
    } do
      assert {:ok, vv} =
               Storybox.Stories.WorldViewVersion
               |> Ash.ActionInput.for_action(:cut, %{world_view_id: wv.id})
               |> Ash.run_action()

      assert vv.version_number == 1
      assert vv.world_view_id == wv.id
    end

    test "creates exactly one Segment with view_version_type :world_vv", %{world_view: wv} do
      {:ok, vv} =
        Storybox.Stories.WorldViewVersion
        |> Ash.ActionInput.for_action(:cut, %{world_view_id: wv.id})
        |> Ash.run_action()

      segments =
        Storybox.Stories.Segment
        |> Ash.Query.filter(view_version_id == ^vv.id)
        |> Ash.read!(authorize?: false)

      assert length(segments) == 1
      [seg] = segments
      assert seg.view_version_type == :world_vv
    end

    test "Segment carries correct pin_id, pin_type, pin_version_at_creation, and position", %{
      world_view: wv,
      piece: piece
    } do
      {:ok, vv} =
        Storybox.Stories.WorldViewVersion
        |> Ash.ActionInput.for_action(:cut, %{world_view_id: wv.id})
        |> Ash.run_action()

      [seg] =
        Storybox.Stories.Segment
        |> Ash.Query.filter(view_version_id == ^vv.id)
        |> Ash.read!(authorize?: false)

      assert seg.pin_id == piece.id
      assert seg.pin_type == :world_piece
      assert seg.pin_version_at_creation == piece.version_number
      assert seg.position == 1
    end

    test "second cut produces version_number 2", %{world_view: wv} do
      {:ok, _vv1} =
        Storybox.Stories.WorldViewVersion
        |> Ash.ActionInput.for_action(:cut, %{world_view_id: wv.id})
        |> Ash.run_action()

      {:ok, vv2} =
        Storybox.Stories.WorldViewVersion
        |> Ash.ActionInput.for_action(:cut, %{world_view_id: wv.id})
        |> Ash.run_action()

      assert vv2.version_number == 2
    end

    test "Segment.resolve_pin/1 returns {:resolved, %WorldPiece{}}", %{
      world_view: wv,
      piece: piece
    } do
      {:ok, vv} =
        Storybox.Stories.WorldViewVersion
        |> Ash.ActionInput.for_action(:cut, %{world_view_id: wv.id})
        |> Ash.run_action()

      [seg] =
        Storybox.Stories.Segment
        |> Ash.Query.filter(view_version_id == ^vv.id)
        |> Ash.read!(authorize?: false)

      assert {:resolved, resolved_piece} = Storybox.Stories.Segment.resolve_pin(seg)
      assert resolved_piece.id == piece.id
      assert resolved_piece.content_uri == piece.content_uri
    end
  end
end
