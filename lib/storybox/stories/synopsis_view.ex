defmodule Storybox.Stories.SynopsisView do
  use Ash.Resource,
    domain: Storybox.Stories,
    data_layer: AshPostgres.DataLayer

  require Ash.Query

  postgres do
    table "synopsis_views"
    repo Storybox.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :content_uri, :string, allow_nil?: false, public?: true
    attribute :version_number, :integer, allow_nil?: false, public?: true

    create_timestamp :inserted_at
  end

  relationships do
    belongs_to :story, Storybox.Stories.Story, allow_nil?: false, public?: true
  end

  actions do
    defaults [:read]

    create :create do
      accept [:story_id, :content_uri, :version_number]
    end

    action :create_version, :struct do
      constraints instance_of: Storybox.Stories.SynopsisView
      argument :content, :string, allow_nil?: false
      argument :story_id, :uuid, allow_nil?: false

      run fn input, _context ->
        story_id = input.arguments.story_id

        existing_views =
          Storybox.Stories.SynopsisView
          |> Ash.Query.filter(story_id == ^story_id)
          |> Ash.read!(authorize?: false)

        next_version_number =
          existing_views
          |> Enum.map(& &1.version_number)
          |> Enum.max(fn -> 0 end)
          |> Kernel.+(1)

        uri = Storybox.Storage.uri_for_synopsis(story_id, next_version_number)

        with {:ok, _} <- Storybox.Storage.put_content(uri, input.arguments.content) do
          Storybox.Stories.SynopsisView
          |> Ash.Changeset.for_create(:create, %{
            story_id: story_id,
            content_uri: uri,
            version_number: next_version_number
          })
          |> Ash.create(authorize?: false)
        end
      end
    end
  end
end
