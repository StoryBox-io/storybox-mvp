require Ash.Query

# ---------------------------------------------------------------------------
# Dev seed data
#
# Test account — email: dev@storybox.test / password: Password1!
#
# NOTE: This file uses pre-M5 vocabulary (SequencePiece, SequenceVersion,
# ScenePiece, SceneVersion, SynopsisVersion). Issue #74 will rename these to
# TreatmentView, TreatmentPiece, ScriptView, ScriptPiece, SynopsisView.
# Update module references here when #74 lands.
#
# Reference story: Little Witch (pandaChest/projects/story/LittleWitch/)
# The folder structure there mirrors the model:
#   synopsis-{seq}-v{N}.fountain  → SynopsisVersion segments (post #71 redesign)
#   {seq}-v{N}.fountain           → SequenceVersion content
#   scenes/{slug}/script-v{N}.fountain → SceneVersion content
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
    controlling_idea: "True power is earned through hard work. There are no shortcuts. There is no gift.",
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

# ---------------------------------------------------------------------------
# Little Witch — full seed
# ---------------------------------------------------------------------------

if little_witch = all_stories["Little Witch"] do
  # -- World -----------------------------------------------------------------

  existing_world =
    Storybox.Stories.World
    |> Ash.Query.filter(story_id == ^little_witch.id)
    |> Ash.read_one!(authorize?: false)

  if is_nil(existing_world) do
    Storybox.Stories.World
    |> Ash.Changeset.for_create(:create, %{
      history:
        "The Order of Flame trained healers and demon-binders for generations. They wrote the Chosen One prophecy as a political shield — it outlasted them. The Alderman rose through a war that destroyed the Order and inherited the prophecy, deciding it meant whoever controls the Chosen One controls the continent.",
      rules:
        "The threshold between discipline and consumption is the Order's most guarded knowledge. Unglamorous, dangerous work — years of it — before anyone was permitted near a demon. The Alderman's purge continues: wanted posters for witches line every garrison wall.",
      subtext:
        "The prophecy does not need to be true to be useful. The political machinery runs on belief, not fact. What Fleur did in the fire was real not because it was special — because it was work.",
      story_id: little_witch.id
    })
    |> Ash.create!(authorize?: false)

    IO.puts("  Created world for Little Witch")
  end

  # -- Characters ------------------------------------------------------------

  existing_characters =
    Storybox.Stories.Character
    |> Ash.Query.filter(story_id == ^little_witch.id)
    |> Ash.read!(authorize?: false)
    |> Enum.map(& &1.name)

  for {name, attrs} <- [
        {"Fleur",
         %{
           essence:
             "A lonely orphan with half-finished training who mistakes the feeling of being chosen for the fact of it.",
           voice: "Genuine, service-oriented — her good impulses are what make her easy to weaponise.",
           contradictions: ["capable yet unfinished", "grief-driven yet clear-eyed at the end"]
         }},
        {"Kestrel",
         %{
           essence:
             "The Order's former war leader. Imprisoned for a decade. Has spent ten years constructing a picture of Silas's betrayal from incomplete evidence.",
           voice: "Blade-like. Perceptive and strategic. Every word is a move.",
           contradictions: ["honed yet wrong", "engineering revenge yet undoing it"]
         }},
        {"Silas",
         %{
           essence:
             "Fleur's guardian. Never seen on screen after the prologue. The moral centre of the story in absentia.",
           voice: "Quiet. Unglamorous. Her example is the lesson, not her words.",
           contradictions: ["careful yet afraid", "protective yet the source of the vulnerability"]
         }},
        {"The Flame Demon",
         %{
           essence:
             "A cunning elemental parasite who survives by becoming whatever his captor needs most.",
           voice: "Warm, patient, precise. He does not invent hope. He locates it and feeds it.",
           contradictions: ["charming yet consuming", "small yet growing"]
         }},
        {"The Alderman",
         %{
           essence:
             "An expansionist ruler who genuinely believes the prophecy. This makes him more dangerous than a cynic.",
           voice: "Rational given his premise. He is collecting what he believes the world promised him.",
           contradictions: ["sincere yet monstrous", "building peace yet burning people"]
         }}
      ],
      name not in existing_characters do
    Storybox.Stories.Character
    |> Ash.Changeset.for_create(:create, Map.merge(attrs, %{name: name, story_id: little_witch.id}))
    |> Ash.create!(authorize?: false)

    IO.puts("  Created character: #{name}")
  end

  # -- Synopsis versions -----------------------------------------------------
  # NOTE: Current schema uses a monolithic blob per version. Issue #71
  # (Spike S-B) will redesign this to one SynopsisPiece per sequence slot.
  # The per-segment content lives in pandaChest as synopsis-{seq}-v1.fountain.

  existing_synopsis_count =
    Storybox.Stories.SynopsisVersion
    |> Ash.Query.filter(story_id == ^little_witch.id)
    |> Ash.read!(authorize?: false)
    |> length()

  if existing_synopsis_count == 0 do
    Ash.ActionInput.for_action(Storybox.Stories.SynopsisVersion, :create_version, %{
      story_id: little_witch.id,
      content: """
      Fleur is a young orphan raised in isolation by Silas, a healer and former member of the Order of Flame. Silas trained Fleur only in healing — never the full, dangerous discipline of demonkin. When the Alderman's men find Silas, she presses the chest key into Fleur's hands and walks out to meet them. Fleur is left alone.

      The hope that she might be the Chosen One finally has room to breathe. She opens the Book of Demons. The ritual goes catastrophically wrong, burning the cottage to ash. In the ruins, a diminished Flame Demon bargains for survival by finding the hope already inside her and naming it. She shelters him in a lantern and walks toward the capital.

      In the capital, Fleur follows Silas's example — working among the sick and poor, building trust through honest effort. But each time she leans on the demon for help, the honest work shrinks and his influence grows. The Alderman recognises her. He gives her access to the city's prisoners — including Kestrel, the Order's former war leader, imprisoned for a decade. Kestrel plays both sides, steering Fleur toward the fire the same way the war once steered her.

      At the coronation, the demon erupts. The city burns. But Fleur does not collapse — Silas's teaching reasserts itself. She throws herself between the fire and the people with nothing but her own body. Kestrel watches and the calculation breaks. She reaches into the fire and tells Fleur the truth: there is no Chosen One. There never was. The only power that is real is earned. The demon is sealed. Kestrel is diminished. Fleur stands at the beginning of her real training.
      """
    })
    |> Ash.run_action!(authorize?: false)

    IO.puts("  Created synopsis v1 for Little Witch")
  end

  # -- Sequence pieces (TreatmentViews) + versions (TreatmentPieces) ---------

  existing_sequence_count =
    Storybox.Stories.SequencePiece
    |> Ash.Query.filter(story_id == ^little_witch.id)
    |> Ash.read!(authorize?: false)
    |> length()

  if existing_sequence_count == 0 do
    sequences = [
      {1, "Prologue — The Forest Road", "Prologue", """
      Years before the story begins. A forest road at dusk. The Alderman's soldiers hunt Order remnants. Silas — a former Order member living in hiding — intervenes to protect a family and reveals who she was before. She acts with full training, borrows fire from the Book once, and registers the cost immediately. The family is dead. A small girl is left alone in the road. Silas takes her home. The question of what she saw in that moment sits in the prologue like an ember. It will not be answered here.
      """},
      {2, "The Cottage", "Act I", """
      The cottage has become two people's life. Silas has taught Fleur the identification of herbs, the treatment of wounds, the patience of sitting with the sick. Fleur is capable — and restless in a way she can't name. She has heard the Chosen One whispers her whole life. Silas has redirected, gently, consistently, for years.

      The Alderman's soldiers arrive. Silas is calm in the way of someone who has been half-expecting this for a decade. She presses the chest key into Fleur's hands: "Hide. Do good. Never touch the Book." She holds Fleur's face — and then says the thing she has been unable to say: "You are what I should have been."

      She walks out to meet the soldiers. Fleur is left alone in the empty cottage with a key in her hand.
      """},
      {3, "The Summoning", "Act I", """
      Fleur sits with the key for a long time. She turns over Silas's last words and finds a crack in them. She opens the chest. She takes out the Book. The fire stirs before she says the words.

      She attempts the summoning. It goes catastrophically wrong. The fire takes the cottage. In the ash and rain a diminished Flame Demon lies trapped. He looks up at Fleur and says: "There you are. I've been looking for you." He does not invent her hope. He locates it and feeds it.

      Fleur puts him in the iron lantern. She walks away from the burning cottage toward the road.
      """},
      {4, "Settling — Silas's Way", "Act II", """
      Fleur enters the capital with nothing but the lantern. She does what Silas taught her. She tends wounds, sets bones, grinds herbs. Slow, invisible work. She builds a community through presence — not spectacle.

      But the work is slow, and Fleur is afraid. The demon whispers: let me help. Just enough to make her healing look like mundane skill. No one will suspect.

      Fleur accepts. The first shortcut. It works. The pattern is set. Each time Fleur leans on the demon, the honest work gets smaller and his influence grows.
      """},
      {5, "Kestrel's Game", "Act II", """
      The Alderman notices Fleur's half-gestures of trained craft. Rather than burning her, he pauses — a desperate young witch could be useful. He gives her access to the sick, the poor, even the prisoners. His real intention: to parade her before Kestrel.

      In the dungeon, Kestrel reads Silas in Fleur's training gaps — and makes a bitter, wrong reading: Silas took the Book, found an heir, built a private lineage. She tips off the Alderman about the demon, redirecting his plan toward a coronation. Then she works Fleur — filling the void Silas left, weaponising the truth about Silas's flight to crack Fleur's faith. She steers Fleur toward the fire the same way the war once steered her. She knows what she is doing. She does it anyway.
      """},
      {6, "The Tug of War", "Act II", """
      The Alderman grooms Fleur for the coronation — the Chosen One crowned as Solar Queen, his dynasty legitimised. Kestrel advises from behind bars, positioning herself as counterweight while steering Fleur toward the demon. The demon grows. Each shortcut felt reasonable at the time.

      Fleur walks into the coronation with her eyes open, believing she can save the community she built through honest work. The demon surges. Fleur loses control. The city burns. The prophecy is revealed as hollow. There is only destruction, and Fleur put it there.
      """}
    ]

    for {position, title, act, content} <- sequences do
      {:ok, seq} =
        Storybox.Stories.SequencePiece
        |> Ash.Changeset.for_create(:create, %{
          title: title,
          act: act,
          position: position,
          story_id: little_witch.id
        })
        |> Ash.create(authorize?: false)

      uri = Storybox.Storage.uri_for_sequence(little_witch.id, seq.id, 1)
      Storybox.Storage.put_content(uri, String.trim(content))

      {:ok, v1} =
        Storybox.Stories.SequenceVersion
        |> Ash.Changeset.for_create(:create, %{
          sequence_piece_id: seq.id,
          content_uri: uri,
          version_number: 1,
          upstream_status: :current,
          weights: %{"preference" => 0.8, "theme" => 0.7}
        })
        |> Ash.create(authorize?: false)

      seq
      |> Ash.Changeset.for_update(:approve_version, %{version_id: v1.id})
      |> Ash.update!(authorize?: false)
    end

    # Reckoning — two versions: v1 approved (earlier draft), v2 stale (V3 ending)
    # Demonstrates: approved version + newer upstream version = staleness signal
    {:ok, reckoning} =
      Storybox.Stories.SequencePiece
      |> Ash.Changeset.for_create(:create, %{
        title: "Reckoning — Kestrel's Choice",
        act: "Act III",
        position: 7,
        story_id: little_witch.id
      })
      |> Ash.create(authorize?: false)

    reckoning_v1_uri = Storybox.Storage.uri_for_sequence(little_witch.id, reckoning.id, 1)

    Storybox.Storage.put_content(reckoning_v1_uri, """
    The city is burning. The demon is loose. Fleur stands in the wreckage of everything she believed.

    But Silas's training holds. Fleur puts herself between the fire and the people — not with power, but with her body. She does not stop.

    Kestrel watches and makes her choice. She reaches into the fire and contains the demon using the full discipline she was trained for. It costs her.

    The demon is sealed. Kestrel is diminished. The Alderman's ceremony is over.

    Fleur stands at the beginning of her real training.
    """)

    {:ok, reckoning_v1} =
      Storybox.Stories.SequenceVersion
      |> Ash.Changeset.for_create(:create, %{
        sequence_piece_id: reckoning.id,
        content_uri: reckoning_v1_uri,
        version_number: 1,
        upstream_status: :current,
        weights: %{"preference" => 0.6, "theme" => 0.5}
      })
      |> Ash.create(authorize?: false)

    # Approve v1
    reckoning
    |> Ash.Changeset.for_update(:approve_version, %{version_id: reckoning_v1.id})
    |> Ash.update!(authorize?: false)

    reckoning_v2_uri = Storybox.Storage.uri_for_sequence(little_witch.id, reckoning.id, 2)

    Storybox.Storage.put_content(reckoning_v2_uri, """
    The city is burning. The demon is loose. Fleur stands in the wreckage of everything she believed.

    But Fleur does not collapse. In the worst moment of her life, Silas's teaching reasserts itself — not the knowledge Silas withheld, but the lesson she gave every day without words. Fleur gives everything she has to shield the townsfolk — with her body, her hands, her voice. Her face and arm are seared. She does not stop.

    Kestrel sees Fleur in the fire and the calculation breaks. She recognises what she has done — specifically, not in the abstract. She reaches into the fire and contains the demon at full cost. Then she tells Fleur the truth: there is no Chosen One. There never was. The Alderman made it up. The demon used it. Kestrel used it. The only power that is real is the kind you earn — slowly, painfully, with no guarantee of success. What Fleur did in the fire was real. Not because it was special. Because it was work.

    The demon is sealed back in the lantern. Kestrel is diminished — perhaps dying, perhaps simply spent. The Alderman's political machinery grinds on. The world has not been saved by a single act of fire. What has changed is Fleur.
    """)

    {:ok, _reckoning_v2} =
      Storybox.Stories.SequenceVersion
      |> Ash.Changeset.for_create(:create, %{
        sequence_piece_id: reckoning.id,
        content_uri: reckoning_v2_uri,
        version_number: 2,
        upstream_status: :stale,
        weights: %{}
      })
      |> Ash.create(authorize?: false)

    IO.puts("  Created 7 sequence pieces for Little Witch (reckoning has v1 approved + v2 stale)")
  end

  # -- Scene pieces (ScriptViews) + versions (ScriptPieces) ------------------
  # Scenes are seeded under two sequences: Summoning (3 scenes) and Reckoning (2 scenes).
  # The final Reckoning scene has no version — demonstrates unresolvable view → Task.

  summoning =
    Storybox.Stories.SequencePiece
    |> Ash.Query.filter(story_id == ^little_witch.id and title == "The Summoning")
    |> Ash.read_one!(authorize?: false)

  reckoning =
    Storybox.Stories.SequencePiece
    |> Ash.Query.filter(story_id == ^little_witch.id and title == "Reckoning — Kestrel's Choice")
    |> Ash.read_one!(authorize?: false)

  if summoning do
    existing_summoning_scenes =
      Storybox.Stories.ScenePiece
      |> Ash.Query.filter(sequence_piece_id == ^summoning.id)
      |> Ash.read!(authorize?: false)
      |> length()

    if existing_summoning_scenes == 0 do
      summoning_scenes = [
        {1, "INT. COTTAGE - NIGHT", """
        INT. COTTAGE - NIGHT

        The cottage is dark. FLEUR stands at the chest, key in hand.

        She has been standing here a long time.

        She opens the chest. Lifts out the BOOK OF DEMONS.

        It is heavy and old and warm in a way that stone should not be warm.

        The fire in the hearth shifts toward her.

        FLEUR
        (to herself)
        I'm just looking.

        She opens the cover. Turns to the first page.

        The hearth fire doubles.

        Fleur does not close the Book.
        """},
        {2, "EXT. COTTAGE - NIGHT", """
        EXT. COTTAGE - NIGHT

        Fire. The cottage burns from the inside out.

        FLEUR stands in the yard, hands raised, trying to unsay something.

        The herbs. The medicines. The chest. Years of Silas.

        All of it burning.

        She cannot stop it. She does not move.

        The fire crests the roof. Sparks rise into the dark.

        A long beat. Rain begins.

        The fire and the rain fight each other.

        Fleur is still standing there when the rain wins.
        """},
        {3, "EXT. RUINS - DAWN", """
        EXT. RUINS - DAWN

        Ash and water. The cottage is a shell. Rain has kept the fire from spreading.

        The FLAME DEMON lies trapped in a hollow at the base of the ruined hearth, held by the pooling water. He is small. Diminished.

        He looks up at FLEUR.

        A long beat.

        FLAME DEMON
        There you are. I've been looking for you.

        FLEUR
        You burned my house.

        FLAME DEMON
        (gently)
        You opened the Book.

        Fleur looks at the lantern in her hand. She looks at the demon.

        She opens the lantern.

        He flows into it like heat rising. The lantern brightens once — then settles.

        Fleur closes it. Holds it.

        She starts walking toward the road.
        """}
      ]

      for {position, title, content} <- summoning_scenes do
        {:ok, scene} =
          Storybox.Stories.ScenePiece
          |> Ash.Changeset.for_create(:create, %{
            title: title,
            position: position,
            sequence_piece_id: summoning.id
          })
          |> Ash.create(authorize?: false)

        uri = Storybox.Storage.uri_for_scene(little_witch.id, scene.id, 1)
        Storybox.Storage.put_content(uri, String.trim(content))

        {:ok, v1} =
          Storybox.Stories.SceneVersion
          |> Ash.Changeset.for_create(:create, %{
            scene_piece_id: scene.id,
            content_uri: uri,
            version_number: 1,
            upstream_status: :current,
            weights: %{"preference" => 0.9, "theme" => 0.8}
          })
          |> Ash.create(authorize?: false)

        scene
        |> Ash.Changeset.for_update(:approve_version, %{version_id: v1.id})
        |> Ash.update!(authorize?: false)
      end

      IO.puts("  Created 3 scene pieces for The Summoning (all approved)")
    end
  end

  if reckoning do
    existing_reckoning_scenes =
      Storybox.Stories.ScenePiece
      |> Ash.Query.filter(sequence_piece_id == ^reckoning.id)
      |> Ash.read!(authorize?: false)
      |> length()

    if existing_reckoning_scenes == 0 do
      # Scene 1 — coronation fire (has approved script)
      {:ok, scene_coronation} =
        Storybox.Stories.ScenePiece
        |> Ash.Changeset.for_create(:create, %{
          title: "EXT. CORONATION SQUARE - NIGHT",
          position: 1,
          sequence_piece_id: reckoning.id
        })
        |> Ash.create(authorize?: false)

      coronation_uri = Storybox.Storage.uri_for_scene(little_witch.id, scene_coronation.id, 1)

      Storybox.Storage.put_content(coronation_uri, """
      EXT. CORONATION SQUARE - NIGHT

      The city is burning. Crowds flee in every direction. The Alderman's ceremony has dissolved into ash and screaming.

      The FLAME DEMON is loose in the fire — visible as something that moves against the wind, that chooses where it burns.

      FLEUR stands at the edge of the square. The lantern is empty.

      She has nothing.

      She walks toward the flames.

      She pulls a WOMAN from a burning doorway.

      She runs back out.

      She goes again.

      KESTREL watches from across the square. Still. Reading.

      Fleur's sleeve catches. She beats it out without stopping. Pulls a CHILD from beneath a fallen beam. Carries him.

      She goes back.

      Her face is wrong — one side of it, from the heat. She does not stop.

      Kestrel watches.

      The calculation breaks.
      """)

      {:ok, coronation_v1} =
        Storybox.Stories.SceneVersion
        |> Ash.Changeset.for_create(:create, %{
          scene_piece_id: scene_coronation.id,
          content_uri: coronation_uri,
          version_number: 1,
          upstream_status: :current,
          weights: %{"preference" => 0.9, "theme" => 1.0}
        })
        |> Ash.create(authorize?: false)

      scene_coronation
      |> Ash.Changeset.for_update(:approve_version, %{version_id: coronation_v1.id})
      |> Ash.update!(authorize?: false)

      # Scene 2 — Kestrel's choice (NO script version — unresolvable → Task)
      {:ok, _scene_kestrel} =
        Storybox.Stories.ScenePiece
        |> Ash.Changeset.for_create(:create, %{
          title: "EXT. RUINS — KESTREL'S CHOICE",
          position: 2,
          sequence_piece_id: reckoning.id
        })
        |> Ash.create(authorize?: false)

      IO.puts(
        "  Created 2 scene pieces for Reckoning (1 approved, 1 empty — unresolvable → Task)"
      )
    end
  end
end
