require Ash.Query

# ---------------------------------------------------------------------------
# Dev seed data
#
# Test account — email: dev@storybox.test / password: Password1!
#
# Reference story: Little Witch (pandaChest/projects/story/LittleWitch/)
# The folder structure there mirrors the model:
#   synopsis-{seq}-v{N}.fountain  → SynopsisView segments (post #71 redesign)
#   {seq}-v{N}.fountain           → TreatmentPiece content
#   scenes/{slug}/script-v{N}.fountain → ScriptPiece content
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
      "True power is earned through hard work. There are no shortcuts. There is no gift.",
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
           voice:
             "Genuine, service-oriented — her good impulses are what make her easy to weaponise.",
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
           contradictions: [
             "careful yet afraid",
             "protective yet the source of the vulnerability"
           ]
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
           voice:
             "Rational given his premise. He is collecting what he believes the world promised him.",
           contradictions: ["sincere yet monstrous", "building peace yet burning people"]
         }}
      ],
      name not in existing_characters do
    Storybox.Stories.Character
    |> Ash.Changeset.for_create(
      :create,
      Map.merge(attrs, %{name: name, story_id: little_witch.id})
    )
    |> Ash.create!(authorize?: false)

    IO.puts("  Created character: #{name}")
  end

  # -- Synopsis versions -----------------------------------------------------
  # NOTE: Current schema uses a monolithic blob per version. Issue #71
  # (Spike S-B) will redesign this to one SynopsisPiece per sequence slot.
  # The per-segment content lives in pandaChest as synopsis-{seq}-v1.fountain.

  existing_synopsis_count =
    Storybox.Stories.SynopsisView
    |> Ash.Query.filter(story_id == ^little_witch.id)
    |> Ash.read!(authorize?: false)
    |> length()

  if existing_synopsis_count == 0 do
    Ash.ActionInput.for_action(Storybox.Stories.SynopsisView, :create_version, %{
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

  # -- Scene entities + ScriptViews + ScriptPieces ----------------------------
  # Five scenes seeded directly under the story (no slot intermediary).
  # The final scene has no script version — demonstrates unresolvable → Task.

  existing_scene_count =
    Storybox.Stories.Scene
    |> Ash.Query.filter(story_id == ^little_witch.id)
    |> Ash.read!(authorize?: false)
    |> length()

  if existing_scene_count == 0 do
    seed_scene = fn story_id, title, content ->
      {:ok, scene} =
        Storybox.Stories.Scene
        |> Ash.Changeset.for_create(:create, %{
          title: title,
          story_id: story_id
        })
        |> Ash.create(authorize?: false)

      {:ok, script_view} =
        Storybox.Stories.ScriptView
        |> Ash.Changeset.for_create(:create, %{
          title: title,
          scene_id: scene.id
        })
        |> Ash.create(authorize?: false)

      if content do
        uri = Storybox.Storage.uri_for_scene(story_id, script_view.id, 1)
        Storybox.Storage.put_content(uri, String.trim(content))

        {:ok, v1} =
          Storybox.Stories.ScriptPiece
          |> Ash.Changeset.for_create(:create, %{
            script_view_id: script_view.id,
            content_uri: uri,
            version_number: 1,
            upstream_status: :current,
            weights: %{"preference" => 0.9, "theme" => 0.8}
          })
          |> Ash.create(authorize?: false)

        script_view
        |> Ash.Changeset.for_update(:approve_version, %{version_id: v1.id})
        |> Ash.update!(authorize?: false)
      end

      {scene, script_view}
    end

    scenes = [
      {"INT. COTTAGE - NIGHT",
       """
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
      {"EXT. COTTAGE - NIGHT",
       """
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
      {"EXT. RUINS - DAWN",
       """
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
       """},
      {"EXT. CORONATION SQUARE - NIGHT",
       """
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
       """},
      # Scene 5 — no script version (unresolvable → Task)
      {"EXT. RUINS — KESTREL'S CHOICE", nil}
    ]

    [{cottage_scene, cottage_script_view} | _rest] =
      for {title, content} <- scenes do
        seed_scene.(little_witch.id, title, content)
      end

    # Add a v2 to the first scene (cottage) so snapshot/diff tests have something to compare.
    # v1 stays approved; v2 is unapproved.
    v2_uri = Storybox.Storage.uri_for_scene(little_witch.id, cottage_script_view.id, 2)

    Storybox.Storage.put_content(v2_uri, """
    INT. COTTAGE - NIGHT

    The cottage is dark. FLEUR stands at the chest, key in hand. She has not moved in an hour.

    The hearth fire watches her. She knows it is watching.

    FLEUR
    (quietly, not to herself)
    I know you're there.

    The fire shifts. Not a flare — a lean.

    She turns the key. Lifts the BOOK OF DEMONS out of the chest. It is heavier than she remembers.

    She does not open it yet. She sets it on the table and looks at it.

    FLEUR (CONT'D)
    Silas said never. She didn't say why.

    A long beat. The fire leans further.

    Fleur opens the cover.
    """)

    {:ok, _v2} =
      Storybox.Stories.ScriptPiece
      |> Ash.Changeset.for_create(:create, %{
        script_view_id: cottage_script_view.id,
        content_uri: v2_uri,
        version_number: 2,
        upstream_status: :current,
        weights: %{}
      })
      |> Ash.create(authorize?: false)

    _ = cottage_scene

    IO.puts(
      "  Created 5 scenes for Little Witch (cottage has v1 approved + v2 draft; last scene empty)"
    )
  end
end
