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

    return_v1_uri = Storybox.Storage.uri_for_sequence(long_road.id, piece_return.id, 1)

    Storybox.Storage.put_content(
      return_v1_uri,
      "Frank steps off the bus onto the main street of Millhaven. The town looks the same but feels foreign. He stands on the sidewalk with his duffel bag, watching strangers pass. Nobody recognises him yet."
    )

    {:ok, return_v1} =
      Storybox.Stories.SequenceVersion
      |> Ash.Changeset.for_create(:create, %{
        sequence_piece_id: piece_return.id,
        content_uri: return_v1_uri,
        version_number: 1,
        upstream_status: :current,
        weights: %{"preference" => 0.8, "theme" => 0.6}
      })
      |> Ash.create(authorize?: false)

    return_v2_uri = Storybox.Storage.uri_for_sequence(long_road.id, piece_return.id, 2)

    Storybox.Storage.put_content(
      return_v2_uri,
      "Frank arrives in Millhaven. Revised to open on Ruth watching from the hardware store window before Frank sees her — establishes her perspective first. The town's indifference to his return is the point."
    )

    {:ok, _return_v2} =
      Storybox.Stories.SequenceVersion
      |> Ash.Changeset.for_create(:create, %{
        sequence_piece_id: piece_return.id,
        content_uri: return_v2_uri,
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

    old_faces_v1_uri = Storybox.Storage.uri_for_sequence(long_road.id, piece_old_faces.id, 1)

    Storybox.Storage.put_content(
      old_faces_v1_uri,
      "Frank walks into Sullivan's bar. Hank Sullivan is behind the counter — they served together. The reunion is warm but guarded. Frank asks about people he knew. Some have moved on, some didn't come back."
    )

    {:ok, old_faces_v1} =
      Storybox.Stories.SequenceVersion
      |> Ash.Changeset.for_create(:create, %{
        sequence_piece_id: piece_old_faces.id,
        content_uri: old_faces_v1_uri,
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

  # Scene pieces for "The Return" (only seed if none exist for that sequence)
  the_return =
    Storybox.Stories.SequencePiece
    |> Ash.Query.filter(story_id == ^long_road.id and title == "The Return")
    |> Ash.read_one!(authorize?: false)

  if the_return do
    existing_scene_count =
      Storybox.Stories.ScenePiece
      |> Ash.Query.filter(sequence_piece_id == ^the_return.id)
      |> Ash.read!(authorize?: false)
      |> length()

    if existing_scene_count == 0 do
      # Scene 1 — Homecoming (approved v1, stale v2)
      {:ok, scene_homecoming} =
        Storybox.Stories.ScenePiece
        |> Ash.Changeset.for_create(:create, %{
          title: "Homecoming",
          position: 1,
          sequence_piece_id: the_return.id
        })
        |> Ash.create(authorize?: false)

      homecoming_v1_uri =
        Storybox.Storage.uri_for_scene(long_road.id, scene_homecoming.id, 1)

      Storybox.Storage.put_content(homecoming_v1_uri, """
      INT. MILLHAVEN BUS DEPOT - DAY

      The bus pulls in. Steam. A handful of passengers step off.

      FRANK MALONE (34, lean, careful eyes) steps onto the platform. He sets down his duffel bag and looks at the street.

      It's the same street. Something is different. Him, maybe.

      He picks up the bag and walks.
      """)

      {:ok, homecoming_v1} =
        Storybox.Stories.SceneVersion
        |> Ash.Changeset.for_create(:create, %{
          scene_piece_id: scene_homecoming.id,
          content_uri: homecoming_v1_uri,
          version_number: 1,
          upstream_status: :current,
          weights: %{"preference" => 0.9, "theme" => 0.7}
        })
        |> Ash.create(authorize?: false)

      homecoming_v2_uri =
        Storybox.Storage.uri_for_scene(long_road.id, scene_homecoming.id, 2)

      Storybox.Storage.put_content(homecoming_v2_uri, """
      EXT. MILLHAVEN MAIN STREET - DAY

      RUTH MALONE (32) stands in the window of the hardware store. She watches the street.

      A bus pulls up at the far end. Passengers step off. One of them stops and just stands there.

      Ruth leans closer to the glass.

      INT. HARDWARE STORE - CONTINUOUS

      She moves to the door. Opens it. Steps outside.

      The man is still standing there. He hasn't seen her yet.
      """)

      {:ok, _homecoming_v2} =
        Storybox.Stories.SceneVersion
        |> Ash.Changeset.for_create(:create, %{
          scene_piece_id: scene_homecoming.id,
          content_uri: homecoming_v2_uri,
          version_number: 2,
          upstream_status: :stale,
          weights: %{}
        })
        |> Ash.create(authorize?: false)

      # Approve v1
      scene_homecoming
      |> Ash.Changeset.for_update(:approve_version, %{version_id: homecoming_v1.id})
      |> Ash.update!(authorize?: false)

      # Scene 2 — The Platform (no approved version)
      {:ok, scene_platform} =
        Storybox.Stories.ScenePiece
        |> Ash.Changeset.for_create(:create, %{
          title: "The Platform",
          position: 2,
          sequence_piece_id: the_return.id
        })
        |> Ash.create(authorize?: false)

      platform_v1_uri =
        Storybox.Storage.uri_for_scene(long_road.id, scene_platform.id, 1)

      Storybox.Storage.put_content(platform_v1_uri, """
      EXT. MILLHAVEN BUS DEPOT - DAY

      Frank walks to the far end of the platform. He stops at a payphone. Picks up the receiver.

      Holds it.

      Puts it back.

      He wasn't ready to call yet. He picks up his bag and walks into town.
      """)

      {:ok, _platform_v1} =
        Storybox.Stories.SceneVersion
        |> Ash.Changeset.for_create(:create, %{
          scene_piece_id: scene_platform.id,
          content_uri: platform_v1_uri,
          version_number: 1,
          upstream_status: :current,
          weights: %{"preference" => 0.5}
        })
        |> Ash.create(authorize?: false)

      # Scene 3 — First Night (no versions)
      {:ok, _scene_first_night} =
        Storybox.Stories.ScenePiece
        |> Ash.Changeset.for_create(:create, %{
          title: "First Night",
          position: 3,
          sequence_piece_id: the_return.id
        })
        |> Ash.create(authorize?: false)

      IO.puts("  Created 3 scene pieces for The Return")
    end
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
