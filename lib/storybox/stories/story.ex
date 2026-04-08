defmodule Storybox.Stories.Story do
  use Ash.Resource,
    domain: Storybox.Stories,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "stories"
    repo Storybox.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :title, :string, allow_nil?: false, public?: true
    attribute :logline, :string, allow_nil?: true, public?: true
    attribute :controlling_idea, :string, allow_nil?: true, public?: true
    attribute :through_lines, {:array, :string}, default: ["preference"], public?: true

    timestamps()
  end

  relationships do
    belongs_to :user, Storybox.Accounts.User, allow_nil?: false, public?: true
    has_many :characters, Storybox.Stories.Character, public?: true
    has_one :world, Storybox.Stories.World, public?: true
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:title, :logline, :controlling_idea, :through_lines, :user_id]
    end

    update :update do
      accept [:title, :logline, :controlling_idea, :through_lines]
    end
  end
end
