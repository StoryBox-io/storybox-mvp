defmodule StoryboxWeb.ScriptViewHelpers do
  @moduledoc """
  Shared fixture builders for the script-view endpoint tests.

  Builds the V/VV stack the endpoint traverses —
  `StoryScriptView → SequenceView → ScriptView → ScriptPiece` — and is used
  by both the JSON (`ScriptViewTest`) and Fountain (`ScriptViewFountainTest`)
  test modules. `import StoryboxWeb.ScriptViewHelpers` to use it.
  """

  alias Storybox.Stories.{
    Scene,
    ScriptPiece,
    ScriptView,
    ScriptViewVersion,
    Segment,
    Sequence,
    SequenceView,
    SequenceViewVersion,
    Story,
    StoryScriptView,
    StoryScriptViewVersion
  }

  def create_story(user, title) do
    {:ok, story} =
      Story
      |> Ash.Changeset.for_create(:create, %{title: title, user_id: user.id})
      |> Ash.create()

    story
  end

  def create_scene(story, label) do
    {:ok, scene} =
      Scene
      |> Ash.Changeset.for_create(:create, %{slug: Slug.slugify(label), story_id: story.id})
      |> Ash.create(authorize?: false)

    scene
  end

  def create_script_view(scene) do
    {:ok, sv} =
      ScriptView
      |> Ash.Changeset.for_create(:create, %{scene_id: scene.id})
      |> Ash.create(authorize?: false)

    sv
  end

  def create_script_piece(scene, content) do
    {:ok, piece} =
      ScriptPiece
      |> Ash.ActionInput.for_action(:create_version, %{scene_id: scene.id, content: content})
      |> Ash.run_action(authorize?: false)

    piece
  end

  def create_script_vv(script_view, version_number, piece) do
    {:ok, vv} =
      ScriptViewVersion
      |> Ash.Changeset.for_create(:create, %{
        script_view_id: script_view.id,
        version_number: version_number
      })
      |> Ash.create(authorize?: false)

    create_segment(vv.id, :script_vv, 1, pin(:script_piece, piece))
    vv
  end

  def create_sequence(story, name, slug) do
    {:ok, seq} =
      Sequence
      |> Ash.Changeset.for_create(:create, %{story_id: story.id, name: name, slug: slug})
      |> Ash.create(authorize?: false)

    seq
  end

  def create_sequence_view(story, sequence) do
    {:ok, sv} =
      SequenceView
      |> Ash.Changeset.for_create(:create, %{story_id: story.id, sequence_id: sequence.id})
      |> Ash.create(authorize?: false)

    sv
  end

  def create_sequence_vv(sequence_view, version_number, pins) do
    {:ok, vv} =
      SequenceViewVersion
      |> Ash.Changeset.for_create(:create, %{
        sequence_view_id: sequence_view.id,
        version_number: version_number
      })
      |> Ash.create(authorize?: false)

    create_pinned_segments(vv.id, :sequence_vv, pins)
    vv
  end

  def create_story_script_view(story) do
    {:ok, ssv} =
      StoryScriptView
      |> Ash.Changeset.for_create(:create, %{story_id: story.id})
      |> Ash.create(authorize?: false)

    ssv
  end

  def create_story_script_vv(story_script_view, version_number, pins) do
    {:ok, vv} =
      StoryScriptViewVersion
      |> Ash.Changeset.for_create(:create, %{
        story_script_view_id: story_script_view.id,
        version_number: version_number,
        source_treatment_view_version_id: Ash.UUID.generate()
      })
      |> Ash.create(authorize?: false)

    create_pinned_segments(vv.id, :story_script_vv, pins)
    vv
  end

  # `pin/2` produces the {pin_type, pin_id, pin_version} tuple a Segment needs.
  def pin(pin_type, target), do: {pin_type, target.id, target.version_number}

  def create_pinned_segments(view_version_id, view_version_type, pins) do
    pins
    |> Enum.with_index(1)
    |> Enum.each(fn {pin, position} ->
      create_segment(view_version_id, view_version_type, position, pin)
    end)
  end

  def create_segment(view_version_id, view_version_type, position, pin) do
    attrs = %{
      view_version_id: view_version_id,
      view_version_type: view_version_type,
      position: position
    }

    attrs =
      case pin do
        nil ->
          attrs

        {pin_type, pin_id, pin_version} ->
          Map.merge(attrs, %{
            pin_id: pin_id,
            pin_type: pin_type,
            pin_version_at_creation: pin_version
          })
      end

    {:ok, seg} =
      Segment
      |> Ash.Changeset.for_create(:create, attrs)
      |> Ash.create(authorize?: false)

    seg
  end
end
