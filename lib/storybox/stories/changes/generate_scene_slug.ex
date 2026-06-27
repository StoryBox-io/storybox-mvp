defmodule Storybox.Stories.Changes.GenerateSceneSlug do
  use Ash.Resource.Change

  # On create, derive `slug` from `slugline` when no explicit slug is supplied.
  # An explicit slug always wins. If neither slug nor a sluggable slugline is
  # present, the changeset is left untouched so the `allow_nil?: false`
  # constraint on `slug` surfaces a validation error.
  def change(changeset, _opts, _context) do
    case Ash.Changeset.get_attribute(changeset, :slug) do
      slug when is_binary(slug) and slug != "" ->
        changeset

      _ ->
        case Ash.Changeset.get_attribute(changeset, :slugline) do
          slugline when is_binary(slugline) and slugline != "" ->
            case Slug.slugify(slugline, separator: "_") do
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
