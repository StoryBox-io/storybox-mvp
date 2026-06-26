defmodule StoryboxWeb.StoryOverviewLive do
  use StoryboxWeb, :live_view

  require Ash.Query

  @impl true
  def mount(%{"story_id" => story_id}, _session, socket) do
    case socket.assigns[:current_user] do
      nil ->
        {:ok, redirect(socket, to: ~p"/sign-in")}

      user ->
        story =
          Storybox.Stories.Story
          |> Ash.Query.filter(id == ^story_id and user_id == ^user.id)
          |> Ash.read_one!(authorize?: false)

        case story do
          nil ->
            {:ok,
             socket
             |> put_flash(:error, "Story not found.")
             |> redirect(to: ~p"/")}

          story ->
            characters =
              Storybox.Stories.Character
              |> Ash.Query.filter(story_id == ^story.id)
              |> Ash.read!(authorize?: false)

            characters_with_content =
              for character <- characters do
                {character, resolve_character_content(character.id)}
              end

            world =
              Storybox.Stories.World
              |> Ash.Query.filter(story_id == ^story.id)
              |> Ash.read_one!(authorize?: false)

            {world_content, world_vv_inserted_at} =
              case world do
                nil -> {nil, nil}
                w -> resolve_world_content(w.id)
              end

            synopsis_view =
              Storybox.Stories.SynopsisView
              |> Ash.Query.filter(story_id == ^story.id)
              |> Ash.read_one!(authorize?: false)

            synopsis_view_versions =
              case synopsis_view do
                nil ->
                  []

                sv ->
                  Storybox.Stories.SynopsisViewVersion
                  |> Ash.Query.filter(synopsis_view_id == ^sv.id)
                  |> Ash.Query.sort(version_number: :desc)
                  |> Ash.read!(authorize?: false)
              end

            {:ok,
             assign(socket,
               story: story,
               characters_with_content: characters_with_content,
               world: world,
               world_content: world_content,
               world_vv_inserted_at: world_vv_inserted_at,
               synopsis_view_versions: synopsis_view_versions,
               page_title: story.title
             )}
        end
    end
  end

  defp resolve_character_content(character_id) do
    character_view =
      Storybox.Stories.CharacterView
      |> Ash.Query.filter(character_id == ^character_id)
      |> Ash.read_one!(authorize?: false)

    with cv when not is_nil(cv) <- character_view,
         [vv | _] <-
           Storybox.Stories.CharacterViewVersion
           |> Ash.Query.filter(character_view_id == ^cv.id)
           |> Ash.Query.sort(version_number: :desc)
           |> Ash.read!(authorize?: false),
         [seg | _] <-
           Storybox.Stories.Segment
           |> Ash.Query.filter(view_version_id == ^vv.id and view_version_type == :character_vv)
           |> Ash.read!(authorize?: false),
         {:resolved, piece} <- Storybox.Stories.Segment.resolve_pin(seg),
         {:ok, content} <- Storybox.Storage.get_content(piece.content_uri) do
      content
    else
      _ -> nil
    end
  end

  defp resolve_world_content(world_id) do
    world_view =
      Storybox.Stories.WorldView
      |> Ash.Query.filter(world_id == ^world_id)
      |> Ash.read_one!(authorize?: false)

    with wv when not is_nil(wv) <- world_view,
         [vv | _] <-
           Storybox.Stories.WorldViewVersion
           |> Ash.Query.filter(world_view_id == ^wv.id)
           |> Ash.Query.sort(version_number: :desc)
           |> Ash.read!(authorize?: false),
         [seg | _] <-
           Storybox.Stories.Segment
           |> Ash.Query.filter(view_version_id == ^vv.id and view_version_type == :world_vv)
           |> Ash.read!(authorize?: false),
         {:resolved, piece} <- Storybox.Stories.Segment.resolve_pin(seg),
         {:ok, content} <- Storybox.Storage.get_content(piece.content_uri) do
      {content, vv.inserted_at}
    else
      _ -> {nil, nil}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div class="space-y-8">
        <div class="flex items-center justify-between">
          <.link navigate={~p"/"} class="text-sm text-base-content/60 hover:text-base-content">
            ← Back to stories
          </.link>
        </div>

        <div class="space-y-2">
          <h1 class="text-3xl font-bold">{@story.title}</h1>
          <%= if @story.logline do %>
            <p class="text-base-content/70">{@story.logline}</p>
          <% end %>
          <%= if @story.controlling_idea do %>
            <p class="text-base-content/60 text-sm">
              <span class="font-medium">Controlling idea:</span> {@story.controlling_idea}
            </p>
          <% end %>
        </div>

        <section class="space-y-3">
          <h2 class="text-xl font-semibold">Characters</h2>
          <%= if @characters_with_content == [] do %>
            <p class="text-base-content/60 text-sm">No characters defined yet.</p>
          <% else %>
            <ul class="space-y-2">
              <%= for {character, content} <- @characters_with_content do %>
                <li class="card bg-base-200 shadow-sm">
                  <div class="card-body py-3">
                    <h3 class="card-title text-base">{character.name}</h3>
                    <%= if content do %>
                      <p class="text-base-content/70 text-sm whitespace-pre-line">{content}</p>
                    <% end %>
                  </div>
                </li>
              <% end %>
            </ul>
          <% end %>
        </section>

        <section class="space-y-3">
          <h2 class="text-xl font-semibold">World</h2>
          <%= if @world == nil do %>
            <p class="text-base-content/60 text-sm">No world defined yet.</p>
          <% else %>
            <div class="card bg-base-200 shadow-sm">
              <div class="card-body space-y-3">
                <%= if @world_content do %>
                  <p class="text-sm whitespace-pre-line">{@world_content}</p>
                <% end %>
                <%= if @world_vv_inserted_at do %>
                  <p class="text-xs text-base-content/40">
                    Last updated: {Calendar.strftime(@world_vv_inserted_at, "%B %-d, %Y")}
                  </p>
                <% end %>
              </div>
            </div>
          <% end %>
        </section>

        <section class="space-y-3">
          <h2 class="text-xl font-semibold">Synopsis</h2>
          <%= if @synopsis_view_versions == [] do %>
            <p class="text-base-content/60 text-sm">No synopsis versions yet.</p>
          <% else %>
            <ul class="space-y-2">
              <%= for {vv, index} <- Enum.with_index(@synopsis_view_versions) do %>
                <li class="card bg-base-100 shadow-sm">
                  <div class="card-body py-3 flex flex-row items-center gap-3">
                    <span class="font-mono font-semibold">v{vv.version_number}</span>
                    <span class="text-base-content/60 text-sm">
                      {Calendar.strftime(vv.inserted_at, "%B %-d, %Y")}
                    </span>
                    <%= if index == 0 do %>
                      <span class="badge badge-success badge-sm">Latest</span>
                    <% end %>
                  </div>
                </li>
              <% end %>
            </ul>
          <% end %>
        </section>
      </div>
    </Layouts.app>
    """
  end
end
