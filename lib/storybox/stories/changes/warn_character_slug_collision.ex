defmodule Storybox.Stories.Changes.WarnCharacterSlugCollision do
  use Ash.Resource.Change

  require Ash.Query
  require Logger

  alias Storybox.Stories.Character

  # After a Scene is created or updated, surface a non-fatal warning when its
  # slug is coupled to a Character slug in the same Story. The Scene slug is split
  # into tokens on `-`/`_` and each token is compared against every Character's
  # stored `slug`. A match logs a warning but never blocks the action.
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
    |> Ash.Query.select([:id, :name, :slug])
    |> Ash.read!(authorize?: false)
    |> Enum.each(fn character ->
      if MapSet.member?(tokens, character.slug) do
        Logger.warning(
          "Scene slug #{inspect(scene.slug)} collides with Character " <>
            "#{inspect(character.name)} in story #{scene.story_id}"
        )
      end
    end)

    {:ok, scene}
  end
end
