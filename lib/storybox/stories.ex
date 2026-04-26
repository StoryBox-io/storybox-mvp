defmodule Storybox.Stories do
  use Ash.Domain

  resources do
    resource Storybox.Stories.Story
    resource Storybox.Stories.Character
    resource Storybox.Stories.World
    resource Storybox.Stories.SynopsisView
    resource Storybox.Stories.TreatmentView
    resource Storybox.Stories.TreatmentPiece
    resource Storybox.Stories.ScriptView
    resource Storybox.Stories.ScriptPiece
    resource Storybox.Stories.Scene
    resource Storybox.Stories.TreatmentViewScene
    resource Storybox.Stories.ScriptSnapshot
    resource Storybox.Stories.UpstreamChange
  end
end
