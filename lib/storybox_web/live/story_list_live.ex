defmodule StoryboxWeb.StoryListLive do
  use StoryboxWeb, :live_view

  require Ash.Query

  @impl true
  def mount(_params, _session, socket) do
    case socket.assigns[:current_user] do
      nil ->
        {:ok, redirect(socket, to: ~p"/sign-in")}

      user ->
        stories =
          Storybox.Stories.Story
          |> Ash.Query.filter(user_id == ^user.id)
          |> Ash.Query.sort(inserted_at: :desc)
          |> Ash.read!(authorize?: false)

        {:ok, assign(socket, stories: stories, page_title: "My Stories")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div class="space-y-6">
        <div class="flex items-center justify-between">
          <h1 class="text-2xl font-bold">My Stories</h1>
        </div>

        <%= if @stories == [] do %>
          <p class="text-base-content/60">No stories yet. Start writing your first story.</p>
        <% else %>
          <ul class="space-y-4">
            <%= for story <- @stories do %>
              <li class="card bg-base-200 shadow-sm">
                <div class="card-body py-4">
                  <h2 class="card-title text-lg">{story.title}</h2>
                  <%= if story.logline do %>
                    <p class="text-base-content/70 text-sm">{story.logline}</p>
                  <% end %>
                  <p class="text-base-content/40 text-xs">
                    Created {Calendar.strftime(story.inserted_at, "%B %-d, %Y")}
                  </p>
                </div>
              </li>
            <% end %>
          </ul>
        <% end %>
      </div>
    </Layouts.app>
    """
  end
end
