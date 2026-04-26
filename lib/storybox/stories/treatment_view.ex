defmodule Storybox.Stories.TreatmentView do
  use Ash.Resource,
    domain: Storybox.Stories,
    data_layer: AshPostgres.DataLayer

  require Ash.Query

  postgres do
    table "treatment_views"
    repo Storybox.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :title, :string, allow_nil?: false, public?: true
    attribute :act, :string, allow_nil?: true, public?: true
    attribute :position, :integer, allow_nil?: false, public?: true
    attribute :approved_version_id, :uuid, allow_nil?: true, public?: true

    timestamps()
  end

  relationships do
    belongs_to :story, Storybox.Stories.Story, allow_nil?: false, public?: true
    has_many :treatment_pieces, Storybox.Stories.TreatmentPiece, public?: true
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:title, :act, :position, :story_id]
    end

    update :update do
      accept [:title, :act, :position]
    end

    update :approve_version do
      argument :version_id, :uuid, allow_nil?: false
      change set_attribute(:approved_version_id, arg(:version_id))
    end

    action :create_version, :struct do
      constraints instance_of: Storybox.Stories.TreatmentPiece
      argument :content, :string, allow_nil?: false
      argument :treatment_view_id, :uuid, allow_nil?: false

      run fn input, _context ->
        view_id = input.arguments.treatment_view_id

        [view] =
          Storybox.Stories.TreatmentView
          |> Ash.Query.filter(id == ^view_id)
          |> Ash.read!(authorize?: false)

        existing_pieces =
          Storybox.Stories.TreatmentPiece
          |> Ash.Query.filter(treatment_view_id == ^view_id)
          |> Ash.read!(authorize?: false)

        next_version_number =
          existing_pieces
          |> Enum.map(& &1.version_number)
          |> Enum.max(fn -> 0 end)
          |> Kernel.+(1)

        uri = Storybox.Storage.uri_for_sequence(view.story_id, view_id, next_version_number)

        with {:ok, _} <- Storybox.Storage.put_content(uri, input.arguments.content) do
          Storybox.Stories.TreatmentPiece
          |> Ash.Changeset.for_create(:create, %{
            treatment_view_id: view_id,
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
