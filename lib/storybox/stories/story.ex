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

    timestamps()
  end

  relationships do
    belongs_to :user, Storybox.Accounts.User, allow_nil?: false, public?: true
    has_many :characters, Storybox.Stories.Character, public?: true
    has_many :sequences, Storybox.Stories.Sequence, public?: true
    has_one :world, Storybox.Stories.World, public?: true
    has_many :synopsis_views, Storybox.Stories.SynopsisView, public?: true
    has_many :synopsis_pieces, Storybox.Stories.SynopsisPiece, public?: true
    has_many :sequence_pieces, Storybox.Stories.SequencePiece, public?: true

    has_many :scenes, Storybox.Stories.Scene, public?: true

    has_one :treatment_view, Storybox.Stories.TreatmentView, public?: true
    has_many :sequence_views, Storybox.Stories.SequenceView, public?: true
    has_one :story_script_view, Storybox.Stories.StoryScriptView, public?: true
    has_one :story_spine, Storybox.Stories.StorySpine, public?: true

    has_one :throughline_view, Storybox.Stories.ThroughlineView, public?: true
    has_many :throughline_pieces, Storybox.Stories.ThroughlinePiece, public?: true
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:title, :logline, :controlling_idea, :user_id]
      change Storybox.Stories.Changes.BootstrapStory
    end

    update :update do
      accept [:title, :logline, :controlling_idea]
    end
  end
end
