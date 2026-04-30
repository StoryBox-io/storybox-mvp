defmodule Storybox.Stories.ScriptSnapshot do
  use Ash.Resource,
    domain: Storybox.Stories,
    data_layer: AshPostgres.DataLayer

  require Ash.Query

  postgres do
    table "script_snapshots"
    repo Storybox.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string, allow_nil?: false, public?: true
    attribute :entries, :map, default: %{}, public?: true

    create_timestamp :inserted_at
  end

  relationships do
    belongs_to :story, Storybox.Stories.Story, allow_nil?: false, public?: true
  end

  actions do
    defaults [:read]

    create :create do
      accept [:name, :entries, :story_id]
    end

    action :capture, :struct do
      constraints instance_of: Storybox.Stories.ScriptSnapshot
      argument :story_id, :uuid, allow_nil?: false
      argument :name, :string, allow_nil?: false

      run fn input, _context ->
        story_id = input.arguments.story_id

        scene_ids =
          Storybox.Stories.Scene
          |> Ash.Query.filter(story_id == ^story_id)
          |> Ash.read!(authorize?: false)
          |> Enum.map(& &1.id)

        entries =
          case scene_ids do
            [] ->
              %{}

            ids ->
              Storybox.Stories.ScriptView
              |> Ash.Query.filter(scene_id in ^ids)
              |> Ash.read!(authorize?: false)
              |> Enum.reject(&is_nil(&1.approved_version_id))
              |> Map.new(fn view ->
                {to_string(view.id), to_string(view.approved_version_id)}
              end)
          end

        Storybox.Stories.ScriptSnapshot
        |> Ash.Changeset.for_create(:create, %{
          story_id: story_id,
          name: input.arguments.name,
          entries: entries
        })
        |> Ash.create(authorize?: false)
      end
    end
  end
end
