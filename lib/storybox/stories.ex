defmodule Storybox.Stories do
  use Ash.Domain

  resources do
    resource Storybox.Stories.Story
    resource Storybox.Stories.Character
    resource Storybox.Stories.CharacterPiece
    resource Storybox.Stories.CharacterView
    resource Storybox.Stories.CharacterViewVersion
    resource Storybox.Stories.Sequence
    resource Storybox.Stories.Segment
    resource Storybox.Stories.World
    resource Storybox.Stories.WorldPiece
    resource Storybox.Stories.WorldView
    resource Storybox.Stories.WorldViewVersion
    resource Storybox.Stories.SynopsisView
    resource Storybox.Stories.SynopsisViewVersion
    resource Storybox.Stories.SynopsisPiece
    resource Storybox.Stories.SequencePiece
    resource Storybox.Stories.ScriptView
    resource Storybox.Stories.ScriptViewVersion
    resource Storybox.Stories.ScriptPiece
    resource Storybox.Stories.Scene
    resource Storybox.Stories.TreatmentView
    resource Storybox.Stories.TreatmentViewVersion
    resource Storybox.Stories.SequenceView
    resource Storybox.Stories.SequenceViewVersion
    resource Storybox.Stories.StoryScriptView
    resource Storybox.Stories.StoryScriptViewVersion
    resource Storybox.Stories.StorySpine
    resource Storybox.Stories.StorySpineEntry
    resource Storybox.Stories.StorySpineViewVersion
    resource Storybox.Stories.StorySpineVvEntry
    resource Storybox.Stories.ThroughlinePiece
    resource Storybox.Stories.ThroughlineView
    resource Storybox.Stories.ThroughlineViewVersion
    resource Storybox.Stories.Task
  end
end
