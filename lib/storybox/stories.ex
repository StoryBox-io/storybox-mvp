defmodule Storybox.Stories do
  use Ash.Domain

  resources do
    resource Storybox.Stories.Story
    resource Storybox.Stories.Character
    resource Storybox.Stories.World
    resource Storybox.Stories.SynopsisVersion
    resource Storybox.Stories.SequencePiece
    resource Storybox.Stories.SequenceVersion
    resource Storybox.Stories.ScenePiece
    resource Storybox.Stories.SceneVersion
    resource Storybox.Stories.ScriptSnapshot
    resource Storybox.Stories.UpstreamChange
  end
end
