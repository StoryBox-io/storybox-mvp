defmodule Storybox.Stories.Changes.WarnCharacterSlugCollision do
  use Ash.Resource.Change

  require Ash.Query
  require Logger

  alias Storybox.Stories.Character

  # After a Scene is created or updated, surface a non-fatal warning when its
  # slug is coupled to a Character name in the same Story. The slug is split into
  # tokens on `-`/`_` and each token is compared against `Slug.slugify/1` of every
  # Character's name. A match logs a warning but never blocks the action.
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, &warn/2)
  end

  defp warn(_changeset, scene) do
    tokens =
      scene.slug
      |> String.split(["-", "_"], trim: true)
      |> MapSet.new()

    Character
    |> Ash.Query.filter(story_id == ^scene.story_id)
    |> Ash.read!(authorize?: false)
    |> Enum.each(fn character ->
      if MapSet.member?(tokens, Slug.slugify(character.name)) do
        Logger.warning(
          "Scene slug #{inspect(scene.slug)} collides with Character " <>
            "#{inspect(character.name)} in story #{scene.story_id}"
        )
      end
    end)

    {:ok, scene}
  end
end
