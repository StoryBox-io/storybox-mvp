defmodule Storybox.Seeds.LittleWitchLoader do
  require Ash.Query

  alias Storybox.Stories.{
    Character,
    CharacterPiece,
    CharacterView,
    CharacterViewVersion,
    Scene,
    ScriptPiece,
    ScriptView,
    ScriptViewVersion,
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
    WorldView,
    WorldViewVersion
  }

  @base_path Path.join(:code.priv_dir(:storybox), "seeds/little_witch")

  def seed!(story) do
    scene_count =
      Scene
      |> Ash.Query.filter(story_id == ^story.id)
      |> Ash.count!(authorize?: false)

    if scene_count > 0 do
      :ok
    else
      do_seed!(story)
    end
  end

  defp do_seed!(story) do
    order = read_json("sequence_order.json")["order"]

    # Phase 1 — Sequences (each registers its own StorySpine entry on create, in
    # `order`, so the later layer cuts read the right live order off the spine).
    sequences_by_slug = create_sequences!(story, order)

    # Phase 2 — SynopsisPieces
    create_synopsis_pieces!(story, sequences_by_slug, order)

    # Phase 3 — SequencePieces
    create_sequence_pieces!(story, sequences_by_slug, order)

    # Phase 4 — Characters
    create_characters!(story)

    # Phase 5 — World
    create_world!(story)

    # Phase 6 — Scenes + ScriptPieces
    {scene_map, _script_view_map, script_vv_map} = create_scenes!(story)

    # Phase 7 — TreatmentView + TreatmentVV
    {:ok, treatment_view} =
      TreatmentView
      |> Ash.ActionInput.for_action(:ensure_for_story, %{story_id: story.id})
      |> Ash.run_action(authorize?: false)

    TreatmentViewVersion
    |> Ash.ActionInput.for_action(:cut, %{treatment_view_id: treatment_view.id})
    |> Ash.run_action!(authorize?: false)

    # Phase 8 — SynopsisView + SynopsisVV
    {:ok, synopsis_view} =
      SynopsisView
      |> Ash.ActionInput.for_action(:ensure_for_story, %{story_id: story.id})
      |> Ash.run_action(authorize?: false)

    SynopsisViewVersion
    |> Ash.ActionInput.for_action(:cut, %{synopsis_view_id: synopsis_view.id})
    |> Ash.run_action!(authorize?: false)

    # Phase 9 — Per-sequence SequenceViews + SequenceVVs
    create_sequence_vvs!(story, sequences_by_slug, order, script_vv_map, scene_map)

    # Phase 10 — StoryScriptView + StoryScriptVV
    {:ok, story_script_view} =
      StoryScriptView
      |> Ash.ActionInput.for_action(:ensure_for_story, %{story_id: story.id})
      |> Ash.run_action(authorize?: false)

    StoryScriptViewVersion
    |> Ash.ActionInput.for_action(:cut, %{story_script_view_id: story_script_view.id})
    |> Ash.run_action!(authorize?: false)

    # Phase 11 — Verify
    creation_tasks =
      Task
      |> Ash.Query.for_read(:list_pending, %{story_id: story.id})
      |> Ash.read!(authorize?: false)
      |> Enum.filter(&(&1.type == :creation))

    if length(creation_tasks) != 1 do
      raise "Expected exactly 1 pending creation Task for Little Witch story, got #{length(creation_tasks)}"
    end

    :ok
  end

  defp create_sequences!(story, order) do
    for slug <- order, into: %{} do
      synopsis_file = Path.join(@base_path, "synopsis-#{slug}-v1.fountain")

      unless File.exists?(synopsis_file) do
        raise "Missing synopsis file for slug #{inspect(slug)}: #{synopsis_file}"
      end

      headers = synopsis_file |> File.read!() |> parse_fountain_headers()
      name = Map.fetch!(headers, "Sequence")

      seq =
        Sequence
        |> Ash.Changeset.for_create(:create, %{
          story_id: story.id,
          name: name,
          slug: slug
        })
        |> Ash.create!(authorize?: false)

      {slug, seq}
    end
  end

  defp create_synopsis_pieces!(story, sequences_by_slug, order) do
    for slug <- order, into: %{} do
      seq = Map.fetch!(sequences_by_slug, slug)

      files =
        Path.wildcard(Path.join(@base_path, "synopsis-#{slug}-v*.fountain"))
        |> Enum.sort_by(&version_from_filename/1)

      pieces =
        for file <- files do
          content = File.read!(file)

          SynopsisPiece
          |> Ash.ActionInput.for_action(:create_version, %{
            story_id: story.id,
            sequence_id: seq.id,
            content: content
          })
          |> Ash.run_action!(authorize?: false)
        end

      {slug, pieces}
    end
  end

  defp create_sequence_pieces!(story, sequences_by_slug, order) do
    for slug <- order do
      seq = Map.fetch!(sequences_by_slug, slug)

      files =
        Path.wildcard(Path.join(@base_path, "#{slug}-v*.fountain"))
        |> Enum.reject(&String.contains?(Path.basename(&1), "synopsis-"))
        |> Enum.sort_by(&version_from_filename/1)

      for file <- files do
        content = File.read!(file)

        SequencePiece
        |> Ash.ActionInput.for_action(:create_version, %{
          story_id: story.id,
          sequence_id: seq.id,
          content: content
        })
        |> Ash.run_action!(authorize?: false)
      end
    end
  end

  defp create_characters!(story) do
    chars_dir = Path.join(@base_path, "characters")

    dirs =
      File.ls!(chars_dir)
      |> Enum.filter(&File.dir?(Path.join(chars_dir, &1)))
      |> Enum.sort()

    for name_dir <- dirs do
      char_dir = Path.join(chars_dir, name_dir)

      profile_files =
        Path.wildcard(Path.join(char_dir, "profile-v*.fountain"))
        |> Enum.sort_by(&version_from_filename/1)

      first_file = List.first(profile_files)
      headers = first_file |> File.read!() |> parse_fountain_headers()
      name = Map.fetch!(headers, "Title")

      char =
        Character
        |> Ash.Changeset.for_create(:create, %{name: name, slug: name_dir, story_id: story.id})
        |> Ash.create!(authorize?: false)

      for file <- profile_files do
        content = File.read!(file)

        CharacterPiece
        |> Ash.ActionInput.for_action(:create_version, %{
          character_id: char.id,
          content: content
        })
        |> Ash.run_action!(authorize?: false)
      end

      {:ok, char_view} =
        CharacterView
        |> Ash.ActionInput.for_action(:ensure_for_character, %{character_id: char.id})
        |> Ash.run_action(authorize?: false)

      CharacterViewVersion
      |> Ash.ActionInput.for_action(:cut, %{character_view_id: char_view.id})
      |> Ash.run_action!(authorize?: false)
    end
  end

  defp create_world!(story) do
    world_dir = Path.join(@base_path, "world/external_world")

    world =
      World
      |> Ash.Changeset.for_create(:create, %{
        story_id: story.id,
        name: "External World",
        slug: "external_world"
      })
      |> Ash.create!(authorize?: false)

    files =
      Path.wildcard(Path.join(world_dir, "world-v*.fountain"))
      |> Enum.sort_by(&version_from_filename/1)

    for file <- files do
      content = File.read!(file)

      WorldPiece
      |> Ash.ActionInput.for_action(:create_version, %{
        world_id: world.id,
        content: content
      })
      |> Ash.run_action!(authorize?: false)
    end

    {:ok, world_view} =
      WorldView
      |> Ash.ActionInput.for_action(:ensure_for_world, %{world_id: world.id})
      |> Ash.run_action(authorize?: false)

    WorldViewVersion
    |> Ash.ActionInput.for_action(:cut, %{world_view_id: world_view.id})
    |> Ash.run_action!(authorize?: false)
  end

  defp create_scenes!(story) do
    scenes_dir = Path.join(@base_path, "scenes")

    scene_slugs =
      File.ls!(scenes_dir)
      |> Enum.filter(&File.dir?(Path.join(scenes_dir, &1)))
      |> Enum.sort()

    {scene_map, script_view_map, script_vv_map} =
      Enum.reduce(scene_slugs, {%{}, %{}, %{}}, fn slug, {scenes, views, vvs} ->
        scene_dir = Path.join(scenes_dir, slug)

        scene =
          Scene
          |> Ash.Changeset.for_create(:create, %{
            motif: authored_motif(slug),
            slug: slug,
            story_id: story.id
          })
          |> Ash.create!(authorize?: false)

        script_view =
          ScriptView
          |> Ash.Changeset.for_create(:create, %{scene_id: scene.id})
          |> Ash.create!(authorize?: false)

        script_files =
          Path.wildcard(Path.join(scene_dir, "script-v*.fountain"))
          |> Enum.sort_by(&version_from_filename/1)

        updated_vvs =
          if script_files != [] do
            for file <- script_files do
              content = File.read!(file)

              ScriptPiece
              |> Ash.ActionInput.for_action(:create_version, %{
                scene_id: scene.id,
                content: content
              })
              |> Ash.run_action!(authorize?: false)
            end

            highest_piece =
              ScriptPiece
              |> Ash.Query.filter(scene_id == ^scene.id)
              |> Ash.Query.sort(version_number: :desc)
              |> Ash.read!(authorize?: false)
              |> List.first()

            vv =
              ScriptViewVersion
              |> Ash.ActionInput.for_action(:cut, %{
                script_view_id: script_view.id,
                script_piece_id: highest_piece.id
              })
              |> Ash.run_action!(authorize?: false)

            Map.put(vvs, slug, vv)
          else
            vvs
          end

        {Map.put(scenes, slug, scene), Map.put(views, slug, script_view), updated_vvs}
      end)

    {scene_map, script_view_map, script_vv_map}
  end

  # Authored, show-agnostic dramatic motifs for the seeded Little Witch scenes,
  # keyed by scene directory slug. A slug with no authored motif falls back to nil
  # (motif is optional). Note `ext_ruins_kestrel` deliberately trips the
  # WarnCharacterSlugCollision warning (slug token "kestrel" matches the Kestrel
  # character) — this is expected and non-fatal; renaming is a later authoring pass.
  defp authored_motif(slug) do
    %{
      "ext_coronation_fire" => "the coronation ceremony ignites into chaos",
      "ext_cottage_night" => "a furtive approach to the cottage under cover of darkness",
      "ext_ruins_dawn" => "the ruins are surveyed at first light",
      "ext_ruins_kestrel" => "a confrontation at the ruins draws out an unexpected presence",
      "int_cottage_night" => "inside the cottage as night closes in around them"
    }[slug]
  end

  defp create_sequence_vvs!(story, sequences_by_slug, order, script_vv_map, scene_map) do
    for slug <- order do
      seq = Map.fetch!(sequences_by_slug, slug)

      {:ok, sv} =
        SequenceView
        |> Ash.ActionInput.for_action(:ensure_for_sequence, %{
          sequence_id: seq.id,
          story_id: story.id
        })
        |> Ash.run_action(authorize?: false)

      cuts = read_json("sequence_views/#{slug}_cuts.json")

      seg_maps =
        Enum.map(cuts["segments"], fn seg ->
          scene = Map.fetch!(scene_map, seg["scene"])

          if is_nil(seg["pin"]) do
            %{"scene_id" => scene.id}
          else
            svv = Map.fetch!(script_vv_map, scene_slug_from_pin(seg["pin"]))

            %{
              "scene_id" => scene.id,
              "pin_id" => svv.id,
              "pin_type" => "script_vv",
              "pin_version_at_creation" => svv.version_number
            }
          end
        end)

      SequenceViewVersion
      |> Ash.ActionInput.for_action(:cut, %{sequence_view_id: sv.id, segments: seg_maps})
      |> Ash.run_action!(authorize?: false)
    end
  end

  defp read_json(rel_path) do
    Path.join(@base_path, rel_path)
    |> File.read!()
    |> Jason.decode!()
  end

  defp parse_fountain_headers(content) do
    content
    |> String.split("\n")
    |> Enum.take_while(&(not String.starts_with?(&1, "===")))
    |> Enum.reduce(%{}, fn line, acc ->
      case String.split(line, ": ", parts: 2) do
        [key, value] -> Map.put(acc, String.trim(key), String.trim(value))
        _ -> acc
      end
    end)
  end

  defp version_from_filename(path) do
    base = Path.basename(path, ".fountain")

    case Regex.run(~r/-v(\d+)$/, base) do
      [_, n] -> String.to_integer(n)
      _ -> 0
    end
  end

  defp scene_slug_from_pin(pin_path) do
    case Regex.run(~r{^scenes/([^/]+)/}, pin_path) do
      [_, slug] -> slug
      _ -> raise "Cannot extract scene slug from pin path: #{inspect(pin_path)}"
    end
  end
end
