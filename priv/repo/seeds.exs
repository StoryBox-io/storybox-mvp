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

# Stories for the dev user
existing_titles =
  Storybox.Stories.Story
  |> Ash.Query.filter(user_id == ^dev_user.id)
  |> Ash.read!(authorize?: false)
  |> Enum.map(& &1.title)

stories = [
  %{
    title: "The Long Road Home",
    logline: "A soldier returns from war to find his hometown unrecognisable.",
    controlling_idea: "Redemption requires accepting what cannot be undone.",
    through_lines: ["preference", "theme"]
  },
  %{
    title: "Beneath the Surface",
    logline: nil,
    controlling_idea: nil,
    through_lines: ["preference"]
  },
  %{
    title: "Echo Chamber",
    logline: "In a world of perfect information, one woman discovers the truth is still hidden.",
    controlling_idea: nil,
    through_lines: ["preference"]
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

# Sub-entities for "The Long Road Home"
if long_road = all_stories["The Long Road Home"] do
  existing_characters =
    Storybox.Stories.Character
    |> Ash.Query.filter(story_id == ^long_road.id)
    |> Ash.read!(authorize?: false)
    |> Enum.map(& &1.name)

  existing_synopsis_count =
    Storybox.Stories.SynopsisVersion
    |> Ash.Query.filter(story_id == ^long_road.id)
    |> Ash.read!(authorize?: false)
    |> length()

  existing_world =
    Storybox.Stories.World
    |> Ash.Query.filter(story_id == ^long_road.id)
    |> Ash.read_one!(authorize?: false)

  # Characters
  for {name, attrs} <- [
        {"Frank Malone",
         %{
           essence: "A man who lost himself in the war and must rediscover what he fought for.",
           voice: "Sparse. Every word costs him something.",
           contradictions: ["gentle yet scarred", "loyal yet absent"]
         }},
        {"Ruth Malone",
         %{
           essence:
             "The woman who kept the family alive while waiting for a man who may never come back.",
           voice: "Warm but guarded. She learned not to hope too loudly.",
           contradictions: ["patient yet resentful", "steadfast yet changed"]
         }}
      ],
      name not in existing_characters do
    Storybox.Stories.Character
    |> Ash.Changeset.for_create(:create, Map.merge(attrs, %{name: name, story_id: long_road.id}))
    |> Ash.create!(authorize?: false)

    IO.puts("  Created character: #{name}")
  end

  # World
  if is_nil(existing_world) do
    Storybox.Stories.World
    |> Ash.Changeset.for_create(:create, %{
      history:
        "A mid-century American mill town that peaked before the war and never recovered. The men who left came back different; the town did too.",
      rules:
        "Grief is private. You work, you endure, you don't complain. Showing weakness is more shameful than suffering.",
      subtext: "The real battle is always at home. The enemy is silence.",
      story_id: long_road.id
    })
    |> Ash.create!(authorize?: false)

    IO.puts("  Created world for The Long Road Home")
  end

  # Sequence pieces and versions (only seed if none exist yet)
  existing_sequence_count =
    Storybox.Stories.SequencePiece
    |> Ash.Query.filter(story_id == ^long_road.id)
    |> Ash.read!(authorize?: false)
    |> length()

  if existing_sequence_count == 0 do
    # Act 1 — The Return
    {:ok, piece_return} =
      Storybox.Stories.SequencePiece
      |> Ash.Changeset.for_create(:create, %{
        title: "The Return",
        act: "Act 1",
        position: 1,
        story_id: long_road.id
      })
      |> Ash.create(authorize?: false)

    {:ok, return_v1} =
      Storybox.Stories.SequenceVersion
      |> Ash.Changeset.for_create(:create, %{
        sequence_piece_id: piece_return.id,
        content_uri: "storybox://stories/#{long_road.id}/sequences/#{piece_return.id}/v1",
        version_number: 1,
        upstream_status: :current,
        weights: %{"preference" => 0.8, "theme" => 0.6}
      })
      |> Ash.create(authorize?: false)

    {:ok, _return_v2} =
      Storybox.Stories.SequenceVersion
      |> Ash.Changeset.for_create(:create, %{
        sequence_piece_id: piece_return.id,
        content_uri: "storybox://stories/#{long_road.id}/sequences/#{piece_return.id}/v2",
        version_number: 2,
        upstream_status: :stale,
        weights: %{}
      })
      |> Ash.create(authorize?: false)

    # Approve v1
    piece_return
    |> Ash.Changeset.for_update(:approve_version, %{version_id: return_v1.id})
    |> Ash.update!(authorize?: false)

    # Act 1 — Old Faces
    {:ok, piece_old_faces} =
      Storybox.Stories.SequencePiece
      |> Ash.Changeset.for_create(:create, %{
        title: "Old Faces",
        act: "Act 1",
        position: 2,
        story_id: long_road.id
      })
      |> Ash.create(authorize?: false)

    {:ok, old_faces_v1} =
      Storybox.Stories.SequenceVersion
      |> Ash.Changeset.for_create(:create, %{
        sequence_piece_id: piece_old_faces.id,
        content_uri: "storybox://stories/#{long_road.id}/sequences/#{piece_old_faces.id}/v1",
        version_number: 1,
        upstream_status: :current,
        weights: %{"preference" => 0.5}
      })
      |> Ash.create(authorize?: false)

    # Approve v1
    piece_old_faces
    |> Ash.Changeset.for_update(:approve_version, %{version_id: old_faces_v1.id})
    |> Ash.update!(authorize?: false)

    # Act 2 — The Silence (no approved version)
    {:ok, _piece_silence} =
      Storybox.Stories.SequencePiece
      |> Ash.Changeset.for_create(:create, %{
        title: "The Silence",
        act: "Act 2",
        position: 3,
        story_id: long_road.id
      })
      |> Ash.create(authorize?: false)

    # (no act) — Epilogue (no versions)
    {:ok, _piece_epilogue} =
      Storybox.Stories.SequencePiece
      |> Ash.Changeset.for_create(:create, %{
        title: "Epilogue",
        act: nil,
        position: 4,
        story_id: long_road.id
      })
      |> Ash.create(authorize?: false)

    IO.puts("  Created 4 sequence pieces for The Long Road Home")
  end

  # Synopsis versions (only seed if none exist yet)
  if existing_synopsis_count == 0 do
    Ash.ActionInput.for_action(Storybox.Stories.SynopsisVersion, :create_version, %{
      story_id: long_road.id,
      content:
        "Frank Malone returns to Millhaven after three years in Korea. The town is quieter than he remembered. His wife Ruth has kept the hardware store open alone. Their son Danny doesn't recognise him. Frank can't sleep — he keeps seeing faces. Over the course of one summer, Frank tries to reclaim his place in a life that moved on without him."
    })
    |> Ash.run_action!(authorize?: false)

    Ash.ActionInput.for_action(Storybox.Stories.SynopsisVersion, :create_version, %{
      story_id: long_road.id,
      content:
        "Frank Malone comes home from Korea to a Millhaven that has already grieved him and moved on. His wife Ruth runs the store. His son Danny is a stranger. Frank carries something back with him — something that has no name in 1953. Over one summer he dismantles and rebuilds himself, piece by piece, learning that redemption is not a return but an arrival somewhere new."
    })
    |> Ash.run_action!(authorize?: false)

    IO.puts("  Created 2 synopsis versions for The Long Road Home")
  end
end
