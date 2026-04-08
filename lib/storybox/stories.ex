defmodule Storybox.Stories do
  use Ash.Domain

  resources do
    resource Storybox.Stories.Story
    resource Storybox.Stories.Character
    resource Storybox.Stories.World
  end
end
