defmodule Storybox.Stories.ScriptViewVersion do
  use Ash.Resource,
    domain: Storybox.Stories,
    data_layer: AshPostgres.DataLayer

  require Ash.Query

  postgres do
    table "script_view_versions"
    repo Storybox.Repo
  end

  attributes do
    uuid_primary_key :id
    attribute :version_number, :integer, allow_nil?: false, public?: true
    create_timestamp :inserted_at
  end

  relationships do
    belongs_to :script_view, Storybox.Stories.ScriptView, allow_nil?: false, public?: true

    has_many :segments, Storybox.Stories.Segment,
      destination_attribute: :view_version_id,
      filter: [view_version_type: :script_vv],
      public?: true
  end

  identities do
    identity :unique_version_per_view, [:script_view_id, :version_number]
  end

  actions do
    defaults [:read]

    create :create do
      accept [:script_view_id, :version_number]
    end

    action :cut, :struct do
      constraints instance_of: Storybox.Stories.ScriptViewVersion
      argument :script_view_id, :uuid, allow_nil?: false
      argument :script_piece_id, :uuid, allow_nil?: false

      run fn input, _context ->
        script_view_id = input.arguments.script_view_id
        script_piece_id = input.arguments.script_piece_id

        piece =
          Storybox.Stories.ScriptPiece
          |> Ash.Query.filter(id == ^script_piece_id)
          |> Ash.read_one!(authorize?: false)

        scene =
          Storybox.Stories.Scene
          |> Ash.Query.filter(id == ^piece.scene_id)
          |> Ash.read_one!(authorize?: false)

        story_id = scene.story_id

        existing_versions =
          Storybox.Stories.ScriptViewVersion
          |> Ash.Query.filter(script_view_id == ^script_view_id)
          |> Ash.read!(authorize?: false)

        next_version_number =
          existing_versions
          |> Enum.map(& &1.version_number)
          |> Enum.max(fn -> 0 end)
          |> Kernel.+(1)

        {:ok, vv} =
          Storybox.Stories.ScriptViewVersion
          |> Ash.Changeset.for_create(:create, %{
            script_view_id: script_view_id,
            version_number: next_version_number
          })
          |> Ash.create(authorize?: false)

        Storybox.Stories.Segment
        |> Ash.Changeset.for_create(:create, %{
          view_version_id: vv.id,
          view_version_type: :script_vv,
          position: 1,
          pin_id: script_piece_id,
          pin_type: :script_piece,
          pin_version_at_creation: piece.version_number
        })
        |> Ash.create!(authorize?: false)

        Storybox.Stories.TaskGeneration.after_cut(
          vv.id,
          :script_vv,
          script_view_id,
          :scene,
          piece.scene_id,
          story_id
        )

        {:ok, vv}
      end
    end
  end
end
