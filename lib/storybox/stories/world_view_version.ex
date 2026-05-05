defmodule Storybox.Stories.WorldViewVersion do
  use Ash.Resource,
    domain: Storybox.Stories,
    data_layer: AshPostgres.DataLayer

  require Ash.Query

  postgres do
    table "world_view_versions"
    repo Storybox.Repo
  end

  attributes do
    uuid_primary_key :id
    attribute :version_number, :integer, allow_nil?: false, public?: true
    create_timestamp :inserted_at
  end

  relationships do
    belongs_to :world_view, Storybox.Stories.WorldView, allow_nil?: false, public?: true

    has_many :segments, Storybox.Stories.Segment,
      destination_attribute: :view_version_id,
      filter: [view_version_type: :world_vv],
      public?: true
  end

  identities do
    identity :unique_version_per_view, [:world_view_id, :version_number]
  end

  actions do
    defaults [:read]

    create :create do
      accept [:world_view_id, :version_number]
    end

    action :cut, :struct do
      constraints instance_of: Storybox.Stories.WorldViewVersion
      argument :world_view_id, :uuid, allow_nil?: false

      run fn input, _context ->
        world_view_id = input.arguments.world_view_id

        world_view =
          Storybox.Stories.WorldView
          |> Ash.Query.filter(id == ^world_view_id)
          |> Ash.read_one!(authorize?: false)

        world_id = world_view.world_id

        latest_piece =
          Storybox.Stories.WorldPiece
          |> Ash.Query.filter(world_id == ^world_id)
          |> Ash.Query.sort(version_number: :desc)
          |> Ash.Query.limit(1)
          |> Ash.read!(authorize?: false)
          |> List.first()

        existing_versions =
          Storybox.Stories.WorldViewVersion
          |> Ash.Query.filter(world_view_id == ^world_view_id)
          |> Ash.read!(authorize?: false)

        next_version_number =
          existing_versions
          |> Enum.map(& &1.version_number)
          |> Enum.max(fn -> 0 end)
          |> Kernel.+(1)

        {:ok, vv} =
          Storybox.Stories.WorldViewVersion
          |> Ash.Changeset.for_create(:create, %{
            world_view_id: world_view_id,
            version_number: next_version_number
          })
          |> Ash.create(authorize?: false)

        if latest_piece do
          Storybox.Stories.Segment
          |> Ash.Changeset.for_create(:create, %{
            view_version_id: vv.id,
            view_version_type: :world_vv,
            position: 1,
            pin_id: latest_piece.id,
            pin_type: :world_piece,
            pin_version_at_creation: latest_piece.version_number
          })
          |> Ash.create!(authorize?: false)
        end

        {:ok, vv}
      end
    end
  end
end
