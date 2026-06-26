require Ash.Query

# ---------------------------------------------------------------------------
# Dev seed data
#
# Test account — email: dev@storybox.test / password: Password1!
# ---------------------------------------------------------------------------

dev_user =
  case Storybox.Accounts.User
       |> Ash.Query.filter(email == "dev@storybox.test")
       |> Ash.read_one!(authorize?: false) do
    nil ->
      Storybox.Accounts.User
      |> Ash.Changeset.for_create(:register_with_password, %{
        email: "dev@storybox.test",
        password: "Password1!",
        password_confirmation: "Password1!"
      })
      |> Ash.create!()

    existing ->
      existing
  end

IO.puts("Dev user ready: #{dev_user.email}")

existing_titles =
  Storybox.Stories.Story
  |> Ash.Query.filter(user_id == ^dev_user.id)
  |> Ash.read!(authorize?: false)
  |> Enum.map(& &1.title)

stories = [
  %{
    title: "Little Witch",
    logline:
      "A girl trained only in healing opens the Book of Demons to find out if she is the Chosen One — and sets in motion a chain of manipulation that will burn the capital and strip away every illusion she has ever held.",
    controlling_idea:
      "True power is earned through hard work. There are no shortcuts. There is no gift."
  },
  %{
    title: "Beneath the Surface",
    logline: nil,
    controlling_idea: nil
  },
  %{
    title: "Echo Chamber",
    logline: "In a world of perfect information, one woman discovers the truth is still hidden.",
    controlling_idea: nil
  }
]

all_stories =
  for attrs <- stories do
    story =
      if attrs.title not in existing_titles do
        s =
          Storybox.Stories.Story
          |> Ash.Changeset.for_create(:create, Map.put(attrs, :user_id, dev_user.id))
          |> Ash.create!(authorize?: false)

        IO.puts("  Created story: #{attrs.title}")
        s
      else
        Storybox.Stories.Story
        |> Ash.Query.filter(user_id == ^dev_user.id and title == ^attrs.title)
        |> Ash.read_one!(authorize?: false)
      end

    {attrs.title, story}
  end
  |> Map.new()

if little_witch = all_stories["Little Witch"] do
  Storybox.Seeds.LittleWitchLoader.seed!(little_witch)
  IO.puts("  Little Witch seeded.")
end
