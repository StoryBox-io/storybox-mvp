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

            world =
              Storybox.Stories.World
              |> Ash.Query.filter(story_id == ^story.id)
              |> Ash.read_one!(authorize?: false)

            synopsis_views =
              Storybox.Stories.SynopsisView
              |> Ash.Query.filter(story_id == ^story.id)
              |> Ash.Query.sort(version_number: :desc)
              |> Ash.read!(authorize?: false)

            latest_synopsis_content =
              case synopsis_views do
                [latest | _] ->
                  case Storybox.Storage.get_content(latest.content_uri) do
                    {:ok, content} -> content
                    _ -> nil
                  end

                [] ->
                  nil
              end

            {:ok,
             assign(socket,
               story: story,
               characters: characters,
               world: world,
               synopsis_views: synopsis_views,
               latest_synopsis_content: latest_synopsis_content,
               page_title: story.title
             )}
        end
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
          <.link
            navigate={~p"/stories/#{@story.id}/treatment"}
            class="text-sm text-base-content/60 hover:text-base-content"
          >
            View Treatment →
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
          <p class="text-base-content/60 text-sm">
            <span class="font-medium">Through lines:</span> {Enum.join(@story.through_lines, ", ")}
          </p>
        </div>

        <section class="space-y-3">
          <h2 class="text-xl font-semibold">Characters</h2>
          <%= if @characters == [] do %>
            <p class="text-base-content/60 text-sm">No characters defined yet.</p>
          <% else %>
            <ul class="space-y-2">
              <%= for character <- @characters do %>
                <li class="card bg-base-200 shadow-sm">
                  <div class="card-body py-3">
                    <h3 class="card-title text-base">{character.name}</h3>
                    <%= if character.essence do %>
                      <p class="text-base-content/70 text-sm">{character.essence}</p>
                    <% end %>
                    <%= if character.voice || character.contradictions not in [nil, []] do %>
                      <details class="mt-1">
                        <summary class="text-xs text-base-content/50 cursor-pointer select-none">
                          Voice &amp; contradictions
                        </summary>
                        <div class="mt-2 space-y-2">
                          <%= if character.voice do %>
                            <p class="text-sm">{character.voice}</p>
                          <% end %>
                          <%= if character.contradictions not in [nil, []] do %>
                            <div class="flex flex-wrap gap-1">
                              <%= for c <- character.contradictions do %>
                                <span class="badge badge-outline badge-sm">{c}</span>
                              <% end %>
                            </div>
                          <% end %>
                        </div>
                      </details>
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
                <%= if @world.history do %>
                  <div>
                    <p class="text-xs font-semibold text-base-content/50 uppercase tracking-wide">
                      History
                    </p>
                    <p class="text-sm mt-1">{@world.history}</p>
                  </div>
                <% end %>
                <%= if @world.rules do %>
                  <div>
                    <p class="text-xs font-semibold text-base-content/50 uppercase tracking-wide">
                      Rules
                    </p>
                    <p class="text-sm mt-1">{@world.rules}</p>
                  </div>
                <% end %>
                <%= if @world.subtext do %>
                  <div>
                    <p class="text-xs font-semibold text-base-content/50 uppercase tracking-wide">
                      Subtext
                    </p>
                    <p class="text-sm mt-1">{@world.subtext}</p>
                  </div>
                <% end %>
                <p class="text-xs text-base-content/40">
                  Last updated: {Calendar.strftime(@world.updated_at, "%B %-d, %Y")}
                </p>
              </div>
            </div>
          <% end %>
        </section>

        <section class="space-y-3">
          <h2 class="text-xl font-semibold">Synopsis</h2>
          <%= if @synopsis_views == [] do %>
            <p class="text-base-content/60 text-sm">No synopsis versions yet.</p>
          <% else %>
            <%= if @latest_synopsis_content do %>
              <div class="card bg-base-200 shadow-sm">
                <div class="card-body">
                  <p class="text-sm whitespace-pre-wrap">{@latest_synopsis_content}</p>
                </div>
              </div>
            <% end %>
            <ul class="space-y-2">
              <%= for {view, index} <- Enum.with_index(@synopsis_views) do %>
                <li class="card bg-base-100 shadow-sm">
                  <div class="card-body py-3 flex flex-row items-center gap-3">
                    <span class="font-mono font-semibold">v{view.version_number}</span>
                    <span class="text-base-content/60 text-sm">
                      {Calendar.strftime(view.inserted_at, "%B %-d, %Y")}
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
