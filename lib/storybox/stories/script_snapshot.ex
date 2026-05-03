defmodule Storybox.Stories.ScriptSnapshot do
  use Ash.Resource,
    domain: Storybox.Stories,
    data_layer: AshPostgres.DataLayer

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

        # approved_version_id removed in issue #94; approval redesigned via
        # ScriptViewVersion. Capture produces empty entries until the new
        # approval mechanism is implemented.
        entries = %{}

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
