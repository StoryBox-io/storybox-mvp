defmodule Storybox.Stories.ScenePiece do
  use Ash.Resource,
    domain: Storybox.Stories,
    data_layer: AshPostgres.DataLayer

  require Ash.Query

  postgres do
    table "scene_pieces"
    repo Storybox.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :title, :string, allow_nil?: false, public?: true
    attribute :position, :integer, allow_nil?: false, public?: true
    attribute :approved_version_id, :uuid, allow_nil?: true, public?: true

    timestamps()
  end

  relationships do
    belongs_to :sequence_piece, Storybox.Stories.SequencePiece, allow_nil?: false, public?: true
    has_many :scene_versions, Storybox.Stories.SceneVersion, public?: true
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:title, :position, :sequence_piece_id]
    end

    update :update do
      accept [:title, :position]
    end

    update :approve_version do
      argument :version_id, :uuid, allow_nil?: false
      change set_attribute(:approved_version_id, arg(:version_id))
    end

    action :create_version, :struct do
      constraints instance_of: Storybox.Stories.SceneVersion
      argument :content_uri, :string, allow_nil?: false
      argument :scene_piece_id, :uuid, allow_nil?: false

      run fn input, _context ->
        piece_id = input.arguments.scene_piece_id

        existing_versions =
          Storybox.Stories.SceneVersion
          |> Ash.Query.filter(scene_piece_id == ^piece_id)
          |> Ash.read!(authorize?: false)

        next_version_number =
          existing_versions
          |> Enum.map(& &1.version_number)
          |> Enum.max(fn -> 0 end)
          |> Kernel.+(1)

        Storybox.Stories.SceneVersion
        |> Ash.Changeset.for_create(:create, %{
          scene_piece_id: input.arguments.scene_piece_id,
          content_uri: input.arguments.content_uri,
          version_number: next_version_number,
          upstream_status: :current,
          weights: %{}
        })
        |> Ash.create(authorize?: false)
      end
    end
  end
end
