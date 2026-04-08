defmodule Storybox.Stories do
  use Ash.Domain

  resources do
    resource Storybox.Stories.Story
  end
end
