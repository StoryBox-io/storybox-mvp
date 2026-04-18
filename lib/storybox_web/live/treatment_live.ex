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
            acts = load_acts(story)

            {:ok,
             socket
             |> assign(:story, story)
             |> assign(:acts, acts)
             |> assign(:content, fetch_primary_content(acts))
             |> assign(:weight_forms, MapSet.new())
             |> assign(:page_title, "#{story.title} — Treatment")}
        end
    end
  end

  @impl true
  def handle_event("toggle_weight_form", %{"version-id" => version_id}, socket) do
    weight_forms =
      if MapSet.member?(socket.assigns.weight_forms, version_id) do
        MapSet.delete(socket.assigns.weight_forms, version_id)
      else
        MapSet.put(socket.assigns.weight_forms, version_id)
      end

    {:noreply, assign(socket, :weight_forms, weight_forms)}
  end

  @impl true
  def handle_event("set_weights", %{"version_id" => version_id, "weights" => raw_weights}, socket) do
    weights = parse_weights(raw_weights)

    version =
      Storybox.Stories.SequenceVersion
      |> Ash.Query.filter(id == ^version_id)
      |> Ash.read_one!(authorize?: false)

    version
    |> Ash.Changeset.for_update(:set_weights, %{weights: weights})
    |> Ash.update!(authorize?: false)

    acts = load_acts(socket.assigns.story)
    weight_forms = MapSet.delete(socket.assigns.weight_forms, version_id)

    {:noreply,
     socket
     |> assign(:acts, acts)
     |> assign(:content, fetch_primary_content(acts))
     |> assign(:weight_forms, weight_forms)}
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

    acts = load_acts(socket.assigns.story)
    {:noreply, socket |> assign(:acts, acts) |> assign(:content, fetch_primary_content(acts))}
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
                        <.link
                          navigate={~p"/stories/#{@story.id}/sequences/#{piece.id}/script"}
                          class="ml-auto text-sm text-base-content/60 hover:text-base-content"
                        >
                          Script →
                        </.link>
                      </div>

                      <% primary = primary_version(piece, versions) %>
                      <%= if primary && Map.get(@content, primary.id) do %>
                        <p class="text-sm text-base-content/80 whitespace-pre-wrap">
                          {Map.get(@content, primary.id)}
                        </p>
                      <% end %>

                      <%= if versions == [] do %>
                        <p class="text-base-content/50 text-sm">No versions yet.</p>
                      <% else %>
                        <div class="space-y-2">
                          <%= for version <- versions do %>
                            <% rs = review_status(version.weights, @story.through_lines) %>
                            <div class={[
                              "rounded p-2 text-sm",
                              if(version.id == piece.approved_version_id,
                                do: "bg-base-300",
                                else: ""
                              ),
                              if(rs == :unreviewed, do: "ring-2 ring-warning", else: "")
                            ]}>
                              <div class="flex flex-wrap items-center gap-2">
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
                                  case rs do
                                    :reviewed -> "badge-info"
                                    :partial -> "badge-warning"
                                    :unreviewed -> "badge-ghost"
                                  end
                                ]}>
                                  {rs}
                                </span>

                                <div class="ml-auto flex items-center gap-2">
                                  <button
                                    class="btn btn-xs btn-ghost"
                                    phx-click="toggle_weight_form"
                                    phx-value-version-id={version.id}
                                  >
                                    Review
                                  </button>

                                  <%= if version.id != piece.approved_version_id do %>
                                    <button
                                      class="btn btn-xs btn-outline"
                                      phx-click="approve_version"
                                      phx-value-piece-id={piece.id}
                                      phx-value-version-id={version.id}
                                    >
                                      Approve
                                    </button>
                                  <% end %>
                                </div>
                              </div>

                              <%= if MapSet.member?(@weight_forms, version.id) do %>
                                <.weight_form
                                  version={version}
                                  through_lines={@story.through_lines}
                                />
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

  defp weight_form(assigns) do
    ~H"""
    <form phx-submit="set_weights" class="mt-3 space-y-2 border-t border-base-300 pt-3">
      <input type="hidden" name="version_id" value={@version.id} />
      <%= for tl <- @through_lines do %>
        <% current = Map.get(@version.weights, tl, 0.0) %>
        <div class="flex items-center gap-3">
          <label class="text-xs text-base-content/70 w-24 shrink-0">{tl}</label>
          <input
            type="range"
            id={"range-#{@version.id}-#{tl}"}
            phx-hook="RangeDisplay"
            name={"weights[#{tl}]"}
            min="0"
            max="1"
            step="0.05"
            value={current}
            class="range range-xs flex-1"
          />
          <span class="text-xs font-mono w-8 text-right">{format_weight(current)}</span>
        </div>
      <% end %>
      <div class="flex justify-end gap-2 pt-1">
        <button
          type="button"
          class="btn btn-xs btn-ghost"
          phx-click="toggle_weight_form"
          phx-value-version-id={@version.id}
        >
          Cancel
        </button>
        <button type="submit" class="btn btn-xs btn-primary">Save</button>
      </div>
    </form>
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
    |> Enum.sort_by(fn {_act, act_pieces} ->
      Enum.min_by(act_pieces, & &1.position).position
    end)
    |> Enum.map(fn {act, act_pieces} ->
      {act,
       Enum.map(act_pieces, fn piece ->
         {piece, Map.get(versions_by_piece, piece.id, [])}
       end)}
    end)
  end

  # Returns the approved version if set, otherwise the latest.
  defp primary_version(piece, versions) do
    case Enum.find(versions, &(&1.id == piece.approved_version_id)) do
      nil -> List.first(versions)
      approved -> approved
    end
  end

  defp fetch_primary_content(acts) do
    acts
    |> Enum.flat_map(fn {_act, pieces_with_versions} ->
      Enum.map(pieces_with_versions, fn {piece, versions} ->
        primary_version(piece, versions)
      end)
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.map(fn version ->
      content =
        case Storybox.Storage.get_content(version.content_uri) do
          {:ok, text} -> text
          _ -> nil
        end

      {version.id, content}
    end)
    |> Map.new()
  end

  defp review_status(weights, through_lines) do
    cond do
      Enum.all?(through_lines, &Map.has_key?(weights, &1)) -> :reviewed
      Enum.any?(through_lines, &Map.has_key?(weights, &1)) -> :partial
      true -> :unreviewed
    end
  end

  defp parse_weights(raw) do
    Map.new(raw, fn {k, v} ->
      case Float.parse(v) do
        {f, _} -> {k, f}
        :error -> {k, 0.0}
      end
    end)
  end

  defp format_weight(v) when is_float(v), do: :erlang.float_to_binary(v, decimals: 2)
  defp format_weight(v) when is_integer(v), do: :erlang.float_to_binary(v * 1.0, decimals: 2)
  defp format_weight(_), do: "—"
end
