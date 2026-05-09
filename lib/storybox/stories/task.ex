defmodule Storybox.Stories.Task do
  use Ash.Resource,
    domain: Storybox.Stories,
    data_layer: AshPostgres.DataLayer

  require Ash.Query

  @component_types [:story, :scene, :character, :world]
  @task_types [:creation, :refinement, :review]
  @task_statuses [:pending, :in_progress, :complete]

  postgres do
    table "tasks"
    repo Storybox.Repo

    custom_indexes do
      index [:story_id, :status, :inserted_at]
      index [:status, :inserted_at]
      index [:component_type, :component_id]
      index [:target_view_id]
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :story_id, :uuid, allow_nil?: false, public?: true

    attribute :component_type, :atom,
      allow_nil?: false,
      public?: true,
      constraints: [one_of: @component_types]

    attribute :component_id, :uuid, allow_nil?: false, public?: true

    attribute :target_view_id, :uuid, allow_nil?: false, public?: true
    attribute :target_view_version_id, :uuid, allow_nil?: true, public?: true
    attribute :target_view_type, :string, allow_nil?: false, public?: true

    attribute :type, :atom,
      allow_nil?: false,
      public?: true,
      constraints: [one_of: @task_types]

    attribute :status, :atom,
      allow_nil?: false,
      public?: true,
      default: :pending,
      constraints: [one_of: @task_statuses]

    attribute :triggered_by_piece_id, :uuid, allow_nil?: true, public?: true
    attribute :triggered_by_piece_type, :string, allow_nil?: true, public?: true
    attribute :triggered_by_piece_version, :integer, allow_nil?: true, public?: true

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  actions do
    defaults [:read]

    create :create do
      accept [
        :story_id,
        :component_type,
        :component_id,
        :target_view_id,
        :target_view_version_id,
        :target_view_type,
        :type,
        :status,
        :triggered_by_piece_id,
        :triggered_by_piece_type,
        :triggered_by_piece_version
      ]
    end

    read :list_pending do
      argument :status, :atom, default: :pending
      argument :story_id, :uuid, allow_nil?: false
      argument :component_id, :uuid, allow_nil?: true
      argument :limit, :integer, allow_nil?: true
      argument :offset, :integer, allow_nil?: true

      prepare fn query, _context ->
        args = query.arguments

        q =
          query
          |> Ash.Query.filter(status == ^args.status)
          |> Ash.Query.filter(story_id == ^args.story_id)
          |> Ash.Query.sort(inserted_at: :asc)

        q =
          if args[:component_id],
            do: Ash.Query.filter(q, component_id == ^args[:component_id]),
            else: q

        q = if args[:limit], do: Ash.Query.limit(q, args[:limit]), else: q
        q = if args[:offset], do: Ash.Query.offset(q, args[:offset]), else: q
        q
      end
    end

    update :mark_in_progress do
      change set_attribute(:status, :in_progress)
    end

    update :mark_complete do
      change set_attribute(:status, :complete)
    end
  end
end
