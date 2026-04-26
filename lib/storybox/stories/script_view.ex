defmodule Storybox.Stories.ScriptView do
  use Ash.Resource,
    domain: Storybox.Stories,
    data_layer: AshPostgres.DataLayer

  require Ash.Query

  postgres do
    table "script_views"
    repo Storybox.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :title, :string, allow_nil?: false, public?: true
    attribute :approved_version_id, :uuid, allow_nil?: true, public?: true

    timestamps()
  end

  relationships do
    belongs_to :scene, Storybox.Stories.Scene, allow_nil?: false, public?: true
    has_many :script_pieces, Storybox.Stories.ScriptPiece, public?: true
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:title, :scene_id]
    end

    update :update do
      accept [:title]
    end

    update :approve_version do
      argument :version_id, :uuid, allow_nil?: false
      change set_attribute(:approved_version_id, arg(:version_id))
    end

    action :create_version, :struct do
      constraints instance_of: Storybox.Stories.ScriptPiece
      argument :content, :string, allow_nil?: false
      argument :script_view_id, :uuid, allow_nil?: false

      run fn input, _context ->
        view_id = input.arguments.script_view_id

        [view] =
          Storybox.Stories.ScriptView
          |> Ash.Query.filter(id == ^view_id)
          |> Ash.read!(authorize?: false)

        [scene] =
          Storybox.Stories.Scene
          |> Ash.Query.filter(id == ^view.scene_id)
          |> Ash.read!(authorize?: false)

        existing_pieces =
          Storybox.Stories.ScriptPiece
          |> Ash.Query.filter(script_view_id == ^view_id)
          |> Ash.read!(authorize?: false)

        next_version_number =
          existing_pieces
          |> Enum.map(& &1.version_number)
          |> Enum.max(fn -> 0 end)
          |> Kernel.+(1)

        uri = Storybox.Storage.uri_for_scene(scene.story_id, view_id, next_version_number)

        with {:ok, _} <- Storybox.Storage.put_content(uri, input.arguments.content) do
          Storybox.Stories.ScriptPiece
          |> Ash.Changeset.for_create(:create, %{
            script_view_id: view_id,
            content_uri: uri,
            version_number: next_version_number,
            upstream_status: :current,
            weights: %{}
          })
          |> Ash.create(authorize?: false)
        end
      end
    end
  end
end
