defmodule Storybox.Stories do
  use Ash.Domain

  resources do
    resource Storybox.Stories.Story
    resource Storybox.Stories.Character
    resource Storybox.Stories.World
    resource Storybox.Stories.SynopsisVersion
    resource Storybox.Stories.SequencePiece
    resource Storybox.Stories.SequenceVersion
  end
end
