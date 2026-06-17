defmodule Storybox.Seeds.LittleWitchLoaderTest do
  use Storybox.DataCase

  require Ash.Query

  alias Storybox.Stories.{
    Character,
    CharacterPiece,
    Scene,
    ScriptPiece,
    ScriptView,
    ScriptViewVersion,
    Segment,
    Sequence,
    SequencePiece,
    SequenceView,
    SequenceViewVersion,
    StoryScriptView,
    StoryScriptViewVersion,
    SynopsisPiece,
    SynopsisView,
    SynopsisViewVersion,
    Task,
    TreatmentView,
    TreatmentViewVersion,
    World,
    WorldPiece,
    WorldView
  }

  setup do
    {:ok, user} =
      Storybox.Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "seed_test@example.com",
        password: "Password1!",
        password_confirmation: "Password1!"
      })
      |> Ash.create()

    {:ok, story} =
      Storybox.Stories.Story
      |> Ash.Changeset.for_create(:create, %{
        title: "Little Witch",
        user_id: user.id
      })
      |> Ash.create()

    %{story: story}
  end

  describe "seed!/1" do
    test "creates all expected resources", %{story: story} do
      assert :ok = Storybox.Seeds.LittleWitchLoader.seed!(story)

      assert 7 = count_for_story(Sequence, story.id)
      assert 7 = count_for_story(SynopsisPiece, story.id)
      assert 8 = count_for_story(SequencePiece, story.id)
      assert 5 = count_for_story(Scene, story.id)

      scene_ids = ids_for_story(Scene, story.id)

      assert 4 =
               ScriptPiece
               |> Ash.Query.filter(scene_id in ^scene_ids)
               |> Ash.count!(authorize?: false)

      script_view_ids =
        ScriptView
        |> Ash.Query.filter(scene_id in ^scene_ids)
        |> Ash.read!(authorize?: false)
        |> Enum.map(& &1.id)

      assert 4 =
               ScriptViewVersion
               |> Ash.Query.filter(script_view_id in ^script_view_ids)
               |> Ash.count!(authorize?: false)

      character_ids = ids_for_story(Character, story.id)

      assert 5 =
               CharacterPiece
               |> Ash.Query.filter(character_id in ^character_ids)
               |> Ash.count!(authorize?: false)

      world_ids =
        World
        |> Ash.Query.filter(story_id == ^story.id)
        |> Ash.read!(authorize?: false)
        |> Enum.map(& &1.id)

      assert 1 =
               WorldPiece
               |> Ash.Query.filter(world_id in ^world_ids)
               |> Ash.count!(authorize?: false)

      world_view_ids =
        WorldView
        |> Ash.Query.filter(world_id in ^world_ids)
        |> Ash.read!(authorize?: false)
        |> Enum.map(& &1.id)

      assert 1 = length(world_view_ids)

      sequence_view_ids =
        SequenceView
        |> Ash.Query.filter(story_id == ^story.id)
        |> Ash.read!(authorize?: false)
        |> Enum.map(& &1.id)

      assert 7 =
               SequenceViewVersion
               |> Ash.Query.filter(sequence_view_id in ^sequence_view_ids)
               |> Ash.count!(authorize?: false)

      synopsis_view_ids =
        SynopsisView
        |> Ash.Query.filter(story_id == ^story.id)
        |> Ash.read!(authorize?: false)
        |> Enum.map(& &1.id)

      assert 1 =
               SynopsisViewVersion
               |> Ash.Query.filter(synopsis_view_id in ^synopsis_view_ids)
               |> Ash.count!(authorize?: false)

      treatment_view_ids =
        TreatmentView
        |> Ash.Query.filter(story_id == ^story.id)
        |> Ash.read!(authorize?: false)
        |> Enum.map(& &1.id)

      assert 1 =
               TreatmentViewVersion
               |> Ash.Query.filter(treatment_view_id in ^treatment_view_ids)
               |> Ash.count!(authorize?: false)

      story_script_view_ids =
        StoryScriptView
        |> Ash.Query.filter(story_id == ^story.id)
        |> Ash.read!(authorize?: false)
        |> Enum.map(& &1.id)

      assert 1 =
               StoryScriptViewVersion
               |> Ash.Query.filter(story_script_view_id in ^story_script_view_ids)
               |> Ash.count!(authorize?: false)
    end

    test "all scenes have a directory-name slug and an authored motif", %{story: story} do
      Storybox.Seeds.LittleWitchLoader.seed!(story)

      scenes =
        Scene
        |> Ash.Query.filter(story_id == ^story.id)
        |> Ash.read!(authorize?: false)

      assert length(scenes) == 5

      expected_slugs =
        MapSet.new([
          "ext_coronation_fire",
          "ext_cottage_night",
          "ext_ruins_dawn",
          "ext_ruins_kestrel",
          "int_cottage_night"
        ])

      assert MapSet.new(scenes, & &1.slug) == expected_slugs

      for scene <- scenes do
        assert is_binary(scene.motif) and scene.motif != "",
               "Scene #{inspect(scene.slug)} has no authored motif"
      end
    end

    test "exactly 1 pending creation task targeting Reckoning SequenceView", %{story: story} do
      Storybox.Seeds.LittleWitchLoader.seed!(story)

      creation_tasks =
        Task
        |> Ash.Query.for_read(:list_pending, %{story_id: story.id})
        |> Ash.read!(authorize?: false)
        |> Enum.filter(&(&1.type == :creation))

      assert length(creation_tasks) == 1
      [task] = creation_tasks
      assert task.target_view_type == "sequence_vv"

      reckoning_seq =
        Sequence
        |> Ash.Query.filter(story_id == ^story.id and slug == "reckoning")
        |> Ash.read_one!(authorize?: false)

      reckoning_sv =
        SequenceView
        |> Ash.Query.filter(sequence_id == ^reckoning_seq.id)
        |> Ash.read_one!(authorize?: false)

      assert task.target_view_id == reckoning_sv.id

      kestrel_scene = scene_by_slug(story.id, "ext_ruins_kestrel")
      assert task.target_scene_id == kestrel_scene.id
    end

    test "Reckoning SequenceVV segments carry scene_id for nil-pin and resolved segments",
         %{story: story} do
      Storybox.Seeds.LittleWitchLoader.seed!(story)

      reckoning_seq =
        Sequence
        |> Ash.Query.filter(story_id == ^story.id and slug == "reckoning")
        |> Ash.read_one!(authorize?: false)

      reckoning_sv =
        SequenceView
        |> Ash.Query.filter(sequence_id == ^reckoning_seq.id)
        |> Ash.read_one!(authorize?: false)

      reckoning_vv =
        SequenceViewVersion
        |> Ash.Query.filter(sequence_view_id == ^reckoning_sv.id)
        |> Ash.read!(authorize?: false)
        |> Enum.max_by(& &1.version_number)

      segments =
        Segment
        |> Ash.Query.filter(
          view_version_id == ^reckoning_vv.id and view_version_type == :sequence_vv
        )
        |> Ash.read!(authorize?: false)

      assert length(segments) == 2

      kestrel_scene = scene_by_slug(story.id, "ext_ruins_kestrel")
      coronation_scene = scene_by_slug(story.id, "ext_coronation_fire")

      nil_pin = Enum.find(segments, &is_nil(&1.pin_id))
      assert nil_pin, "expected a nil-pin segment in the Reckoning SequenceVV"
      assert nil_pin.scene_id == kestrel_scene.id

      resolved = Enum.find(segments, &(not is_nil(&1.pin_id)))
      assert resolved, "expected a resolved segment in the Reckoning SequenceVV"
      assert resolved.scene_id == coronation_scene.id
    end

    test "idempotency — second call is a no-op", %{story: story} do
      Storybox.Seeds.LittleWitchLoader.seed!(story)

      seq_count_before = count_for_story(Sequence, story.id)
      task_count_before = count_creation_tasks(story.id)

      assert :ok = Storybox.Seeds.LittleWitchLoader.seed!(story)

      assert count_for_story(Sequence, story.id) == seq_count_before
      assert count_creation_tasks(story.id) == task_count_before
    end
  end

  defp count_for_story(resource, story_id) do
    resource
    |> Ash.Query.filter(story_id == ^story_id)
    |> Ash.count!(authorize?: false)
  end

  defp ids_for_story(resource, story_id) do
    resource
    |> Ash.Query.filter(story_id == ^story_id)
    |> Ash.read!(authorize?: false)
    |> Enum.map(& &1.id)
  end

  defp count_creation_tasks(story_id) do
    Task
    |> Ash.Query.for_read(:list_pending, %{story_id: story_id})
    |> Ash.read!(authorize?: false)
    |> Enum.filter(&(&1.type == :creation))
    |> length()
  end

  defp scene_by_slug(story_id, slug) do
    Scene
    |> Ash.Query.filter(story_id == ^story_id and slug == ^slug)
    |> Ash.read_one!(authorize?: false)
  end
end
