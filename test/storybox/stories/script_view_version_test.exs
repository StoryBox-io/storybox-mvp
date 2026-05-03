defmodule Storybox.Stories.ScriptViewVersionTest do
  use Storybox.DataCase

  require Ash.Query

  setup do
    {:ok, user} =
      Storybox.Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "svv_test@example.com",
        password: "password123!",
        password_confirmation: "password123!"
      })
      |> Ash.create()

    {:ok, story} =
      Storybox.Stories.Story
      |> Ash.Changeset.for_create(:create, %{title: "Test Story", user_id: user.id})
      |> Ash.create()

    {:ok, scene} =
      Storybox.Stories.Scene
      |> Ash.Changeset.for_create(:create, %{title: "Opening Scene", story_id: story.id})
      |> Ash.create()

    {:ok, script_view} =
      Storybox.Stories.ScriptView
      |> Ash.Changeset.for_create(:create, %{scene_id: scene.id})
      |> Ash.create()

    {:ok, piece} =
      Storybox.Stories.ScriptPiece
      |> Ash.ActionInput.for_action(:create_version, %{
        scene_id: scene.id,
        content: "EXT. PARK - DAY\n\nFirst draft."
      })
      |> Ash.run_action()

    %{scene: scene, script_view: script_view, piece: piece}
  end

  describe "cut" do
    test "creates a ScriptViewVersion with version_number 1 on first call", %{
      script_view: script_view,
      piece: piece
    } do
      assert {:ok, vv} =
               Storybox.Stories.ScriptViewVersion
               |> Ash.ActionInput.for_action(:cut, %{
                 script_view_id: script_view.id,
                 script_piece_id: piece.id
               })
               |> Ash.run_action()

      assert vv.version_number == 1
      assert vv.script_view_id == script_view.id
    end

    test "creates exactly one Segment with view_version_type :script_vv", %{
      script_view: script_view,
      piece: piece
    } do
      {:ok, vv} =
        Storybox.Stories.ScriptViewVersion
        |> Ash.ActionInput.for_action(:cut, %{
          script_view_id: script_view.id,
          script_piece_id: piece.id
        })
        |> Ash.run_action()

      segments =
        Storybox.Stories.Segment
        |> Ash.Query.filter(view_version_id == ^vv.id)
        |> Ash.read!(authorize?: false)

      assert length(segments) == 1
      [seg] = segments
      assert seg.view_version_type == :script_vv
    end

    test "Segment carries correct pin_id, pin_type, and pin_version_at_creation", %{
      script_view: script_view,
      piece: piece
    } do
      {:ok, vv} =
        Storybox.Stories.ScriptViewVersion
        |> Ash.ActionInput.for_action(:cut, %{
          script_view_id: script_view.id,
          script_piece_id: piece.id
        })
        |> Ash.run_action()

      [seg] =
        Storybox.Stories.Segment
        |> Ash.Query.filter(view_version_id == ^vv.id)
        |> Ash.read!(authorize?: false)

      assert seg.pin_id == piece.id
      assert seg.pin_type == :script_piece
      assert seg.pin_version_at_creation == piece.version_number
      assert seg.position == 1
    end

    test "second cut increments version_number to 2", %{
      script_view: script_view,
      piece: piece
    } do
      {:ok, _vv1} =
        Storybox.Stories.ScriptViewVersion
        |> Ash.ActionInput.for_action(:cut, %{
          script_view_id: script_view.id,
          script_piece_id: piece.id
        })
        |> Ash.run_action()

      {:ok, vv2} =
        Storybox.Stories.ScriptViewVersion
        |> Ash.ActionInput.for_action(:cut, %{
          script_view_id: script_view.id,
          script_piece_id: piece.id
        })
        |> Ash.run_action()

      assert vv2.version_number == 2
    end

    test "v1 Segment pin_id unchanged after v2 cut", %{
      script_view: script_view,
      piece: piece,
      scene: scene
    } do
      {:ok, vv1} =
        Storybox.Stories.ScriptViewVersion
        |> Ash.ActionInput.for_action(:cut, %{
          script_view_id: script_view.id,
          script_piece_id: piece.id
        })
        |> Ash.run_action()

      {:ok, piece2} =
        Storybox.Stories.ScriptPiece
        |> Ash.ActionInput.for_action(:create_version, %{
          scene_id: scene.id,
          content: "INT. OFFICE - NIGHT\n\nRevised."
        })
        |> Ash.run_action()

      {:ok, _vv2} =
        Storybox.Stories.ScriptViewVersion
        |> Ash.ActionInput.for_action(:cut, %{
          script_view_id: script_view.id,
          script_piece_id: piece2.id
        })
        |> Ash.run_action()

      [v1_seg] =
        Storybox.Stories.Segment
        |> Ash.Query.filter(view_version_id == ^vv1.id)
        |> Ash.read!(authorize?: false)

      assert v1_seg.pin_id == piece.id
    end
  end
end
