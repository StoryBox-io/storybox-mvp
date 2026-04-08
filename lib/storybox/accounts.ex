defmodule Storybox.Accounts do
  use Ash.Domain

  resources do
    resource Storybox.Accounts.User
    resource Storybox.Accounts.Token
  end
end