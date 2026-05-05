require Ash.Query

# ---------------------------------------------------------------------------
# Dev seed data
#
# Test account — email: dev@storybox.test / password: Password1!
#
# Reference story: Little Witch (pandaChest/projects/story/LittleWitch/)
# The folder structure there mirrors the model:
#   synopsis-{seq}-v{N}.fountain  → SynopsisView segments (post #71 redesign)
#   {seq}-v{N}.fountain           → SequencePiece content
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

  world =
    if is_nil(existing_world) do
      w =
        Storybox.Stories.World
        |> Ash.Changeset.for_create(:create, %{story_id: little_witch.id})
        |> Ash.create!(authorize?: false)

      IO.puts("  Created world for Little Witch")
      w
    else
      existing_world
    end

  existing_world_pieces =
    Storybox.Stories.WorldPiece
    |> Ash.Query.filter(world_id == ^world.id)
    |> Ash.read!(authorize?: false)

  if existing_world_pieces == [] do
    world_content = """
    History: The Order of Flame trained healers and demon-binders for generations. They wrote the Chosen One prophecy as a political shield — it outlasted them. The Alderman rose through a war that destroyed the Order and inherited the prophecy, deciding it meant whoever controls the Chosen One controls the continent.

    Rules: The threshold between discipline and consumption is the Order's most guarded knowledge. Unglamorous, dangerous work — years of it — before anyone was permitted near a demon. The Alderman's purge continues: wanted posters for witches line every garrison wall.

    Subtext: The prophecy does not need to be true to be useful. The political machinery runs on belief, not fact. What Fleur did in the fire was real not because it was special — because it was work.
    """

    Storybox.Stories.WorldPiece
    |> Ash.ActionInput.for_action(:create_version, %{
      world_id: world.id,
      content: String.trim(world_content)
    })
    |> Ash.run_action!(authorize?: false)

    IO.puts("  Created WorldPiece v1 for Little Witch")
  end

  {:ok, world_view} =
    Storybox.Stories.WorldView
    |> Ash.ActionInput.for_action(:ensure_for_world, %{world_id: world.id})
    |> Ash.run_action(authorize?: false)

  IO.puts("  WorldView ready for Little Witch")

  existing_wvv =
    Storybox.Stories.WorldViewVersion
    |> Ash.Query.filter(world_view_id == ^world_view.id)
    |> Ash.read!(authorize?: false)

  if existing_wvv == [] do
    Storybox.Stories.WorldViewVersion
    |> Ash.ActionInput.for_action(:cut, %{world_view_id: world_view.id})
    |> Ash.run_action!(authorize?: false)

    IO.puts("  Cut WorldViewVersion v1 for Little Witch")
  end

  # -- Characters ------------------------------------------------------------

  existing_characters =
    Storybox.Stories.Character
    |> Ash.Query.filter(story_id == ^little_witch.id)
    |> Ash.read!(authorize?: false)

  existing_character_names = Enum.map(existing_characters, & &1.name)

  characters_data = [
    {"Fleur",
     """
     Essence: A lonely orphan with half-finished training who mistakes the feeling of being chosen for the fact of it.

     Voice: Genuine, service-oriented — her good impulses are what make her easy to weaponise.

     Contradictions:
     - capable yet unfinished
     - grief-driven yet clear-eyed at the end
     """},
    {"Kestrel",
     """
     Essence: The Order's former war leader. Imprisoned for a decade. Has spent ten years constructing a picture of Silas's betrayal from incomplete evidence.

     Voice: Blade-like. Perceptive and strategic. Every word is a move.

     Contradictions:
     - honed yet wrong
     - engineering revenge yet undoing it
     """},
    {"Silas",
     """
     Essence: Fleur's guardian. Never seen on screen after the prologue. The moral centre of the story in absentia.

     Voice: Quiet. Unglamorous. Her example is the lesson, not her words.

     Contradictions:
     - careful yet afraid
     - protective yet the source of the vulnerability
     """},
    {"The Flame Demon",
     """
     Essence: A cunning elemental parasite who survives by becoming whatever his captor needs most.

     Voice: Warm, patient, precise. He does not invent hope. He locates it and feeds it.

     Contradictions:
     - charming yet consuming
     - small yet growing
     """},
    {"The Alderman",
     """
     Essence: An expansionist ruler who genuinely believes the prophecy. This makes him more dangerous than a cynic.

     Voice: Rational given his premise. He is collecting what he believes the world promised him.

     Contradictions:
     - sincere yet monstrous
     - building peace yet burning people
     """}
  ]

  all_characters =
    for {name, content} <- characters_data do
      character =
        if name not in existing_character_names do
          c =
            Storybox.Stories.Character
            |> Ash.Changeset.for_create(:create, %{name: name, story_id: little_witch.id})
            |> Ash.create!(authorize?: false)

          IO.puts("  Created character: #{name}")
          c
        else
          Enum.find(existing_characters, &(&1.name == name))
        end

      {character, content}
    end

  for {character, content} <- all_characters do
    existing_pieces =
      Storybox.Stories.CharacterPiece
      |> Ash.Query.filter(character_id == ^character.id)
      |> Ash.read!(authorize?: false)

    if existing_pieces == [] do
      Storybox.Stories.CharacterPiece
      |> Ash.ActionInput.for_action(:create_version, %{
        character_id: character.id,
        content: String.trim(content)
      })
      |> Ash.run_action!(authorize?: false)

      IO.puts("  Created CharacterPiece v1 for #{character.name}")
    end

    {:ok, character_view} =
      Storybox.Stories.CharacterView
      |> Ash.ActionInput.for_action(:ensure_for_character, %{character_id: character.id})
      |> Ash.run_action(authorize?: false)

    existing_cvv =
      Storybox.Stories.CharacterViewVersion
      |> Ash.Query.filter(character_view_id == ^character_view.id)
      |> Ash.read!(authorize?: false)

    if existing_cvv == [] do
      Storybox.Stories.CharacterViewVersion
      |> Ash.ActionInput.for_action(:cut, %{character_view_id: character_view.id})
      |> Ash.run_action!(authorize?: false)

      IO.puts("  Cut CharacterViewVersion v1 for #{character.name}")
    end
  end

  # -- Sequences -------------------------------------------------------------
  # Mirrored from pandaChest/projects/story/LittleWitch (orchestrator-owned).
  # Order matters: SynopsisViewVersion.cut falls back to story.sequences ordered
  # by inserted_at when no TreatmentViewVersion exists yet, so we insert in
  # story order (Act I → Act III).

  existing_sequence_slugs =
    Storybox.Stories.Sequence
    |> Ash.Query.filter(story_id == ^little_witch.id)
    |> Ash.read!(authorize?: false)
    |> Enum.map(& &1.slug)

  sequences_to_seed = [
    {"prologue", "Prologue"},
    {"cottage", "The Cottage"},
    {"summoning", "The Summoning"},
    {"settling", "Settling — Silas's Way"},
    {"kestrel_game", "Kestrel's Game"},
    {"reckoning", "Reckoning — Kestrel's Choice"}
  ]

  sequences_by_slug =
    for {slug, name} <- sequences_to_seed, into: %{} do
      seq =
        if slug not in existing_sequence_slugs do
          s =
            Storybox.Stories.Sequence
            |> Ash.Changeset.for_create(:create, %{
              story_id: little_witch.id,
              name: name,
              slug: slug
            })
            |> Ash.create!(authorize?: false)

          IO.puts("  Created sequence: #{name}")
          s
        else
          Storybox.Stories.Sequence
          |> Ash.Query.filter(story_id == ^little_witch.id and slug == ^slug)
          |> Ash.read_one!(authorize?: false)
        end

      {slug, seq}
    end

  # -- SynopsisPieces --------------------------------------------------------
  # Mirrored from LittleWitch/synopsis-{slug}-v1.fountain. Content is hand-
  # maintained by the orchestrator; when LittleWitch changes, update both.

  synopsis_pieces_v1 = [
    {"prologue",
     """
     ~ Years before the story begins. Silas is revealed in action. A child is found. The question of why is not answered.

     Years before the story begins. The Alderman's soldiers hunt Order remnants on a forest road. Silas — a former Order member living in hiding — intervenes to protect a family and reveals who she was before. She acts with full training, borrows fire from the Book once, and registers the cost immediately. The family does not survive. A small girl is left alone in the road. Silas takes her home. The question of what she saw in that moment sits in the prologue like an ember. It will not be answered here.
     """},
    {"cottage",
     """
     ~ Silas and Fleur's life together. The incomplete training. The Book. Silas is taken. Her last words crack open the question Fleur has never been allowed to finish.

     Fleur is a young orphan raised in isolation by Silas, a healer and former member of the Order of Flame. Silas trained Fleur only in healing — never the full, dangerous discipline of demonkin — because watching Kestrel approach the threshold of consumption broke something in Silas. Fleur is capable and restless, unable to fully believe the work is enough. When the Alderman's men find Silas, she presses the chest key into Fleur's hands, says the thing she has been unable to say — "You are what I should have been" — and walks out to meet them. Fleur is left alone with a key in her hand.
     """},
    {"summoning",
     """
     ~ The hope that she might be the Chosen One finally has room to breathe. The ritual goes wrong. The demon finds the hope already inside her and names it.

     The hope that she might be the Chosen One — absorbed from prophecy-carved walls and travellers' stories her whole life, with no one left to keep it in check — finally has room to breathe. She opens the Book of Demons. The ritual goes catastrophically wrong, burning the cottage to ash. In the ruins, a diminished Flame Demon bargains for survival by finding the hope already inside her and naming it. She shelters him in a lantern and walks toward the capital.
     """},
    {"settling",
     """
     ~ In the capital, Fleur does what Silas taught her. It works. Then the first shortcut. The pattern is set.

     In the capital, Fleur follows Silas's example — working among the sick and poor, building trust through honest effort. She builds a community not through spectacle but through presence. But each time she leans on the demon for help, the honest work shrinks and his influence grows. The pattern is set.
     """},
    {"kestrel_game",
     """
     ~ The Alderman sees opportunity. In the dungeon, Kestrel reads Silas in Fleur's training gaps and plays both sides.

     When the Alderman recognises her, he sees not a witch to burn but the Chosen One his prophecy promised. He gives her access to the city's prisoners — including Kestrel, the Order's former war leader, imprisoned for a decade. Kestrel plays both sides. She tips off the Alderman about the demon, redirecting his plan toward a coronation. She works Fleur — filling the void Silas left, framing the demon as a tool of liberation, weaponising the truth about Silas's flight to crack Fleur's faith in her guardian's restraint. She steers Fleur toward the fire the same way the war once steered her. She knows what she is doing. She does it anyway.
     """},
    {"reckoning",
     """
     ~ Fleur holds. Kestrel sees what she has done. Not redemption — reckoning. The truth is told. Fleur stands at the beginning of her real training.

     At the coronation, the demon erupts. The city burns. But Fleur does not collapse — in the worst moment of her life, Silas's teaching reasserts itself: not the knowledge Silas withheld, but the lesson she gave every day without words. Fleur throws herself between the fire and the people, body and hands and voice, with no power but her own.

     Kestrel watches this and the calculation breaks. She recognises what she has done — specifically, not in the abstract. Every gap in Fleur's training is a threshold Silas pulled back from, and the pattern of those pullbacks is the outline of Kestrel herself. She reaches into the fire and contains the demon the way it should always have been done: with full discipline, at full cost. Then she tells Fleur the truth. There is no Chosen One. There never was. The only power that is real is earned — slowly, at each of the thresholds Silas could not push her through.

     The demon is sealed. Kestrel is diminished. The Alderman's political machinery grinds on. The world has not been saved by a single act of fire. What has changed is Fleur. Scarred and stripped of every illusion, she stands at the beginning of her real training.
     """}
  ]

  for {slug, content} <- synopsis_pieces_v1 do
    sequence = Map.fetch!(sequences_by_slug, slug)

    existing =
      Storybox.Stories.SynopsisPiece
      |> Ash.Query.filter(sequence_id == ^sequence.id)
      |> Ash.read!(authorize?: false)

    if existing == [] do
      Storybox.Stories.SynopsisPiece
      |> Ash.ActionInput.for_action(:create_version, %{
        story_id: little_witch.id,
        sequence_id: sequence.id,
        content: String.trim(content)
      })
      |> Ash.run_action!(authorize?: false)

      IO.puts("  Created synopsis v1: #{slug}")
    end
  end

  # -- SynopsisView (logical header — one per story) -------------------------
  {:ok, synopsis_view} =
    Storybox.Stories.SynopsisView
    |> Ash.ActionInput.for_action(:ensure_for_story, %{story_id: little_witch.id})
    |> Ash.run_action(authorize?: false)

  IO.puts("  SynopsisView ready for Little Witch")

  # -- SynopsisViewVersion v1 (cut) ------------------------------------------
  # Pins the latest SynopsisPiece per Sequence as a Segment.

  existing_svv =
    Storybox.Stories.SynopsisViewVersion
    |> Ash.Query.filter(synopsis_view_id == ^synopsis_view.id)
    |> Ash.read!(authorize?: false)

  if existing_svv == [] do
    Storybox.Stories.SynopsisViewVersion
    |> Ash.ActionInput.for_action(:cut, %{synopsis_view_id: synopsis_view.id})
    |> Ash.run_action!(authorize?: false)

    IO.puts("  Cut SynopsisViewVersion v1 for Little Witch")
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
        uri = Storybox.Storage.uri_for_script_piece(scene.id, 1)
        Storybox.Storage.put_content(uri, String.trim(content))

        {:ok, v1} =
          Storybox.Stories.ScriptPiece
          |> Ash.Changeset.for_create(:create, %{
            scene_id: scene.id,
            content_uri: uri,
            version_number: 1,
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
    v2_uri = Storybox.Storage.uri_for_script_piece(cottage_scene.id, 2)

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
        scene_id: cottage_scene.id,
        content_uri: v2_uri,
        version_number: 2,
        weights: %{}
      })
      |> Ash.create(authorize?: false)

    _ = cottage_script_view

    IO.puts(
      "  Created 5 scenes for Little Witch (cottage has v1 approved + v2 draft; last scene empty)"
    )
  end
end
