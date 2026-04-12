defmodule StoryboxWeb.TreatmentLive do
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
            {:ok,
             socket
             |> assign(:story, story)
             |> assign(:acts, load_acts(story))
             |> assign(:page_title, "#{story.title} — Treatment")}
        end
    end
  end

  @impl true
  def handle_event(
        "approve_version",
        %{"piece-id" => piece_id, "version-id" => version_id},
        socket
      ) do
    piece =
      Storybox.Stories.SequencePiece
      |> Ash.Query.filter(id == ^piece_id)
      |> Ash.read_one!(authorize?: false)

    piece
    |> Ash.Changeset.for_update(:approve_version, %{version_id: version_id})
    |> Ash.update!(authorize?: false)

    {:noreply, assign(socket, :acts, load_acts(socket.assigns.story))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div class="space-y-8">
        <.link
          navigate={~p"/stories/#{@story.id}"}
          class="text-sm text-base-content/60 hover:text-base-content"
        >
          ← Back to overview
        </.link>

        <div class="space-y-1">
          <h1 class="text-3xl font-bold">{@story.title}</h1>
          <p class="text-base-content/60 text-sm">Treatment</p>
        </div>

        <%= if @acts == [] do %>
          <p class="text-base-content/60 text-sm">No sequences yet.</p>
        <% else %>
          <%= for {act_label, pieces_with_versions} <- @acts do %>
            <section class="space-y-3">
              <h2 class="text-lg font-semibold text-base-content/80 border-b border-base-300 pb-1">
                {act_label || "No act"}
              </h2>
              <div class="space-y-3">
                <%= for {piece, versions} <- pieces_with_versions do %>
                  <div class="card bg-base-200 shadow-sm">
                    <div class="card-body py-4 space-y-3">
                      <div class="flex items-center gap-2">
                        <span class="badge badge-outline badge-sm font-mono">#{piece.position}</span>
                        <h3 class="font-semibold">{piece.title}</h3>
                      </div>

                      <%= if versions == [] do %>
                        <p class="text-base-content/50 text-sm">No versions yet.</p>
                      <% else %>
                        <div class="space-y-2">
                          <%= for version <- versions do %>
                            <div class={[
                              "flex flex-wrap items-center gap-2 rounded p-2 text-sm",
                              if(version.id == piece.approved_version_id, do: "bg-base-300", else: "")
                            ]}>
                              <span class="font-mono font-semibold">v{version.version_number}</span>

                              <%= if version.id == piece.approved_version_id do %>
                                <span class="badge badge-success badge-sm">Approved</span>
                              <% end %>

                              <span class={[
                                "badge badge-sm",
                                if(version.upstream_status == :stale,
                                  do: "badge-warning",
                                  else: "badge-ghost"
                                )
                              ]}>
                                {version.upstream_status}
                              </span>

                              <span class={[
                                "badge badge-sm",
                                case review_status(version.weights, @story.through_lines) do
                                  :reviewed -> "badge-info"
                                  :partial -> "badge-warning"
                                  :unreviewed -> "badge-ghost"
                                end
                              ]}>
                                {review_status(version.weights, @story.through_lines)}
                              </span>

                              <%= if version.id != piece.approved_version_id do %>
                                <button
                                  class="btn btn-xs btn-outline ml-auto"
                                  phx-click="approve_version"
                                  phx-value-piece-id={piece.id}
                                  phx-value-version-id={version.id}
                                >
                                  Approve
                                </button>
                              <% end %>
                            </div>
                          <% end %>
                        </div>
                      <% end %>
                    </div>
                  </div>
                <% end %>
              </div>
            </section>
          <% end %>
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  defp load_acts(story) do
    pieces =
      Storybox.Stories.SequencePiece
      |> Ash.Query.filter(story_id == ^story.id)
      |> Ash.Query.sort(position: :asc)
      |> Ash.read!(authorize?: false)

    piece_ids = Enum.map(pieces, & &1.id)

    versions_by_piece =
      case piece_ids do
        [] ->
          %{}

        ids ->
          Storybox.Stories.SequenceVersion
          |> Ash.Query.filter(sequence_piece_id in ^ids)
          |> Ash.Query.sort(version_number: :desc)
          |> Ash.read!(authorize?: false)
          |> Enum.group_by(& &1.sequence_piece_id)
      end

    pieces
    |> Enum.group_by(& &1.act)
    |> Enum.sort_by(fn {act, _} -> {is_nil(act), act} end)
    |> Enum.map(fn {act, act_pieces} ->
      {act,
       Enum.map(act_pieces, fn piece ->
         {piece, Map.get(versions_by_piece, piece.id, [])}
       end)}
    end)
  end

  defp review_status(weights, through_lines) do
    cond do
      Enum.all?(through_lines, &Map.has_key?(weights, &1)) -> :reviewed
      Enum.any?(through_lines, &Map.has_key?(weights, &1)) -> :partial
      true -> :unreviewed
    end
  end
end
