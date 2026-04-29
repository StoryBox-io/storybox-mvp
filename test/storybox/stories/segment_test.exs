defmodule Storybox.Stories.SegmentTest do
  use Storybox.DataCase

  require Ash.Query

  alias Storybox.Stories.Segment

  setup do
    {:ok, user} =
      Storybox.Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "test@example.com",
        password: "password123!",
        password_confirmation: "password123!"
      })
      |> Ash.create()

    {:ok, story} =
      Storybox.Stories.Story
      |> Ash.Changeset.for_create(:create, %{title: "Little Witch", user_id: user.id})
      |> Ash.create()

    {:ok, sequence} =
      Storybox.Stories.Sequence
      |> Ash.Changeset.for_create(:create, %{
        name: "Prologue",
        slug: "prologue",
        story_id: story.id
      })
      |> Ash.create()

    {:ok, scene} =
      Storybox.Stories.Scene
      |> Ash.Changeset.for_create(:create, %{title: "Cottage", story_id: story.id})
      |> Ash.create()

    {:ok, script_view} =
      Storybox.Stories.ScriptView
      |> Ash.Changeset.for_create(:create, %{title: "Cottage", scene_id: scene.id})
      |> Ash.create()

    {:ok, sp1} =
      Storybox.Stories.ScriptView
      |> Ash.ActionInput.for_action(:create_version, %{
        script_view_id: script_view.id,
        content: "INT. COTTAGE - DAY\n\nThe witch stirs."
      })
      |> Ash.run_action()

    {:ok, sp2} =
      Storybox.Stories.ScriptView
      |> Ash.ActionInput.for_action(:create_version, %{
        script_view_id: script_view.id,
        content: "INT. COTTAGE - DAY\n\nThe witch stirs the cauldron."
      })
      |> Ash.run_action()

    vv_id = Ecto.UUID.generate()

    %{
      story: story,
      sequence: sequence,
      scene: scene,
      script_view: script_view,
      sp1: sp1,
      sp2: sp2,
      vv_id: vv_id
    }
  end

  describe "create" do
    test "creates a Segment pinning a ScriptPiece (resolved Pin)", %{
      vv_id: vv_id,
      sp2: sp2
    } do
      assert {:ok, segment} =
               Segment
               |> Ash.Changeset.for_create(:create, %{
                 view_version_id: vv_id,
                 view_version_type: :script_vv,
                 position: 0,
                 pin_id: sp2.id,
                 pin_type: :script_piece,
                 pin_version_at_creation: 2
               })
               |> Ash.create()

      assert segment.view_version_id == vv_id
      assert segment.view_version_type == :script_vv
      assert segment.position == 0
      assert segment.pin_id == sp2.id
      assert segment.pin_type == :script_piece
      assert segment.pin_version_at_creation == 2
      assert is_nil(segment.sequence_id)
    end

    test "creates an unresolvable Segment (placeholder for a :creation Task)", %{
      vv_id: vv_id,
      sequence: sequence
    } do
      assert {:ok, segment} =
               Segment
               |> Ash.Changeset.for_create(:create, %{
                 view_version_id: vv_id,
                 view_version_type: :synopsis_vv,
                 position: 0,
                 sequence_id: sequence.id
               })
               |> Ash.create()

      assert is_nil(segment.pin_id)
      assert is_nil(segment.pin_type)
      assert is_nil(segment.pin_version_at_creation)
      assert segment.sequence_id == sequence.id
    end

    test "rejects a Segment with only pin_id set", %{vv_id: vv_id, sp2: sp2} do
      assert {:error, %Ash.Error.Invalid{} = error} =
               Segment
               |> Ash.Changeset.for_create(:create, %{
                 view_version_id: vv_id,
                 view_version_type: :script_vv,
                 position: 0,
                 pin_id: sp2.id
               })
               |> Ash.create()

      assert Exception.message(error) =~
               "pin_id, pin_type, and pin_version_at_creation must all be set or all be null"
    end

    test "rejects a Segment with only pin_type set", %{vv_id: vv_id} do
      assert {:error, %Ash.Error.Invalid{} = error} =
               Segment
               |> Ash.Changeset.for_create(:create, %{
                 view_version_id: vv_id,
                 view_version_type: :script_vv,
                 position: 0,
                 pin_type: :script_piece
               })
               |> Ash.create()

      assert Exception.message(error) =~
               "pin_id, pin_type, and pin_version_at_creation must all be set or all be null"
    end

    test "rejects a Segment with pin_id+pin_type but no pin_version_at_creation", %{
      vv_id: vv_id,
      sp2: sp2
    } do
      assert {:error, %Ash.Error.Invalid{} = error} =
               Segment
               |> Ash.Changeset.for_create(:create, %{
                 view_version_id: vv_id,
                 view_version_type: :script_vv,
                 position: 0,
                 pin_id: sp2.id,
                 pin_type: :script_piece
               })
               |> Ash.create()

      assert Exception.message(error) =~
               "pin_id, pin_type, and pin_version_at_creation must all be set or all be null"
    end
  end

  describe "DB check constraint backstop" do
    test "raw insert with only pin_id set is rejected by the database", %{vv_id: vv_id, sp2: sp2} do
      sql = """
      INSERT INTO segments (id, view_version_id, view_version_type, position, pin_id, pin_type, pin_version_at_creation, inserted_at)
      VALUES (gen_random_uuid(), $1, $2, $3, $4, NULL, NULL, now() AT TIME ZONE 'utc')
      """

      assert_raise Postgrex.Error, ~r/segments_pin_complete_or_empty/, fn ->
        Ecto.Adapters.SQL.query!(Storybox.Repo, sql, [
          Ecto.UUID.dump!(vv_id),
          "script_vv",
          0,
          Ecto.UUID.dump!(sp2.id)
        ])
      end
    end
  end

  describe "unique position per view_version" do
    test "rejects two Segments at the same (view_version_id, view_version_type, position)", %{
      vv_id: vv_id,
      sequence: sequence
    } do
      {:ok, _} =
        Segment
        |> Ash.Changeset.for_create(:create, %{
          view_version_id: vv_id,
          view_version_type: :script_vv,
          position: 0,
          sequence_id: sequence.id
        })
        |> Ash.create()

      assert {:error, %Ash.Error.Invalid{}} =
               Segment
               |> Ash.Changeset.for_create(:create, %{
                 view_version_id: vv_id,
                 view_version_type: :script_vv,
                 position: 0,
                 sequence_id: sequence.id
               })
               |> Ash.create()
    end

    test "allows the same position across different view_version_ids", %{sequence: sequence} do
      vv_a = Ecto.UUID.generate()
      vv_b = Ecto.UUID.generate()

      {:ok, _} =
        Segment
        |> Ash.Changeset.for_create(:create, %{
          view_version_id: vv_a,
          view_version_type: :script_vv,
          position: 0,
          sequence_id: sequence.id
        })
        |> Ash.create()

      assert {:ok, _} =
               Segment
               |> Ash.Changeset.for_create(:create, %{
                 view_version_id: vv_b,
                 view_version_type: :script_vv,
                 position: 0,
                 sequence_id: sequence.id
               })
               |> Ash.create()
    end

    test "allows the same position across different view_version_types", %{
      vv_id: vv_id,
      sequence: sequence
    } do
      {:ok, _} =
        Segment
        |> Ash.Changeset.for_create(:create, %{
          view_version_id: vv_id,
          view_version_type: :script_vv,
          position: 0,
          sequence_id: sequence.id
        })
        |> Ash.create()

      assert {:ok, _} =
               Segment
               |> Ash.Changeset.for_create(:create, %{
                 view_version_id: vv_id,
                 view_version_type: :synopsis_vv,
                 position: 0,
                 sequence_id: sequence.id
               })
               |> Ash.create()
    end
  end

  describe "resolve_pin/1" do
    test "returns {:resolved, %ScriptPiece{}} for a Segment pinning a ScriptPiece", %{
      vv_id: vv_id,
      sp2: sp2
    } do
      {:ok, segment} =
        Segment
        |> Ash.Changeset.for_create(:create, %{
          view_version_id: vv_id,
          view_version_type: :script_vv,
          position: 0,
          pin_id: sp2.id,
          pin_type: :script_piece,
          pin_version_at_creation: 2
        })
        |> Ash.create()

      assert {:resolved, %Storybox.Stories.ScriptPiece{} = target} = Segment.resolve_pin(segment)
      assert target.id == sp2.id
      assert target.version_number == 2
    end

    test "returns {:unresolvable, segment} for a Segment with null pin_id and pin_type", %{
      vv_id: vv_id,
      sequence: sequence
    } do
      {:ok, segment} =
        Segment
        |> Ash.Changeset.for_create(:create, %{
          view_version_id: vv_id,
          view_version_type: :synopsis_vv,
          position: 0,
          sequence_id: sequence.id
        })
        |> Ash.create()

      assert {:unresolvable, ^segment} = Segment.resolve_pin(segment)
    end

    test "raises ArgumentError for a not-yet-implemented pin_type" do
      segment = %{
        pin_id: Ecto.UUID.generate(),
        pin_type: :synopsis_piece
      }

      assert_raise ArgumentError, ~r/:synopsis_piece/, fn -> Segment.resolve_pin(segment) end
    end
  end

  describe "pin_target_latest_version/1" do
    test "returns the lineage's current latest version_number for a current pin", %{
      vv_id: vv_id,
      sp2: sp2
    } do
      {:ok, segment} =
        Segment
        |> Ash.Changeset.for_create(:create, %{
          view_version_id: vv_id,
          view_version_type: :script_vv,
          position: 0,
          pin_id: sp2.id,
          pin_type: :script_piece,
          pin_version_at_creation: 2
        })
        |> Ash.create()

      assert Segment.pin_target_latest_version(segment) == 2
    end

    test "reflects newer versions in the same lineage (real staleness signal)", %{
      vv_id: vv_id,
      script_view: script_view,
      sp2: sp2
    } do
      {:ok, segment} =
        Segment
        |> Ash.Changeset.for_create(:create, %{
          view_version_id: vv_id,
          view_version_type: :script_vv,
          position: 0,
          pin_id: sp2.id,
          pin_type: :script_piece,
          pin_version_at_creation: 2
        })
        |> Ash.create()

      {:ok, sp3} =
        Storybox.Stories.ScriptView
        |> Ash.ActionInput.for_action(:create_version, %{
          script_view_id: script_view.id,
          content: "INT. COTTAGE - DAY\n\nThe witch stirs the cauldron faster."
        })
        |> Ash.run_action()

      assert sp3.version_number == 3
      latest = Segment.pin_target_latest_version(segment)
      assert latest == 3
      assert segment.pin_version_at_creation < latest
    end

    test "returns nil for an unresolvable Segment", %{vv_id: vv_id, sequence: sequence} do
      {:ok, segment} =
        Segment
        |> Ash.Changeset.for_create(:create, %{
          view_version_id: vv_id,
          view_version_type: :synopsis_vv,
          position: 0,
          sequence_id: sequence.id
        })
        |> Ash.create()

      assert Segment.pin_target_latest_version(segment) == nil
    end

    test "raises ArgumentError for a not-yet-implemented pin_type" do
      segment = %{
        pin_id: Ecto.UUID.generate(),
        pin_type: :synopsis_piece
      }

      assert_raise ArgumentError, ~r/:synopsis_piece/, fn ->
        Segment.pin_target_latest_version(segment)
      end
    end
  end
end
