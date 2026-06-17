defmodule Storybox.Stories.Changes.GenerateCharacterSlug do
  use Ash.Resource.Change

  # On create, derive `slug` from `name` when no explicit slug is supplied.
  # An explicit slug always wins. If neither slug nor a sluggable name is
  # present, the changeset is left untouched so the `allow_nil?: false`
  # constraint on `slug` surfaces a validation error.
  def change(changeset, _opts, _context) do
    case Ash.Changeset.get_attribute(changeset, :slug) do
      slug when is_binary(slug) and slug != "" ->
        changeset

      _ ->
        case Ash.Changeset.get_attribute(changeset, :name) do
          name when is_binary(name) and name != "" ->
            case Slug.slugify(name) do
              slug when is_binary(slug) ->
                Ash.Changeset.force_change_attribute(changeset, :slug, slug)

              _ ->
                changeset
            end

          _ ->
            changeset
        end
    end
  end
end
