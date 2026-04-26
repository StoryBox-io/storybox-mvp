defmodule StoryboxWeb.ScriptLive do
  use StoryboxWeb, :live_view

  require Ash.Query

  @impl true
  def mount(%{"story_id" => story_id, "sequence_id" => sequence_id}, _session, socket) do
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
            treatment_view =
              Storybox.Stories.TreatmentView
              |> Ash.Query.filter(id == ^sequence_id and story_id == ^story.id)
              |> Ash.read_one!(authorize?: false)

            case treatment_view do
              nil ->
                {:ok,
                 socket
                 |> put_flash(:error, "Sequence not found.")
                 |> redirect(to: ~p"/stories/#{story.id}/treatment")}

              treatment_view ->
                {:ok,
                 socket
                 |> assign(:story, story)
                 |> assign(:sequence, treatment_view)
                 |> assign(:scenes, load_scenes(treatment_view))
                 |> assign(:mode, :latest)
                 |> assign(:content, %{})
                 |> assign(:weight_forms, MapSet.new())
                 |> assign(:page_title, "#{story.title} — #{treatment_view.title} Script")}
            end
        end
    end
  end

  @impl true
  def handle_params(%{"mode" => "approved"}, _uri, socket) do
    {:noreply,
     socket
     |> assign(:mode, :approved)
     |> assign(:content, fetch_visible_content(socket.assigns.scenes, :approved))}
  end

  def handle_params(_params, _uri, socket) do
    {:noreply,
     socket
     |> assign(:mode, :latest)
     |> assign(:content, fetch_visible_content(socket.assigns.scenes, :latest))}
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

    piece =
      Storybox.Stories.ScriptPiece
      |> Ash.Query.filter(id == ^version_id)
      |> Ash.read_one!(authorize?: false)

    piece
    |> Ash.Changeset.for_update(:set_weights, %{weights: weights})
    |> Ash.update!(authorize?: false)

    scenes = load_scenes(socket.assigns.sequence)
    weight_forms = MapSet.delete(socket.assigns.weight_forms, version_id)

    {:noreply,
     socket
     |> assign(:scenes, scenes)
     |> assign(:content, fetch_visible_content(scenes, socket.assigns.mode))
     |> assign(:weight_forms, weight_forms)}
  end

  @impl true
  def handle_event(
        "approve_version",
        %{"piece-id" => piece_id, "version-id" => version_id},
        socket
      ) do
    script_view =
      Storybox.Stories.ScriptView
      |> Ash.Query.filter(id == ^piece_id)
      |> Ash.read_one!(authorize?: false)

    script_view
    |> Ash.Changeset.for_update(:approve_version, %{version_id: version_id})
    |> Ash.update!(authorize?: false)

    scenes = load_scenes(socket.assigns.sequence)

    {:noreply,
     socket
     |> assign(:scenes, scenes)
     |> assign(:content, fetch_visible_content(scenes, socket.assigns.mode))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div class="space-y-8">
        <.link
          navigate={~p"/stories/#{@story.id}/treatment"}
          class="text-sm text-base-content/60 hover:text-base-content"
        >
          ← Back to treatment
        </.link>

        <div class="space-y-1">
          <h1 class="text-3xl font-bold">{@story.title}</h1>
          <p class="text-base-content/60 text-sm">{@sequence.title} — Script</p>
        </div>

        <div class="flex gap-2">
          <.link
            patch={~p"/stories/#{@story.id}/sequences/#{@sequence.id}/script"}
            class={["btn btn-sm", if(@mode == :latest, do: "btn-primary", else: "btn-ghost")]}
          >
            Latest
          </.link>
          <.link
            patch={~p"/stories/#{@story.id}/sequences/#{@sequence.id}/script?mode=approved"}
            class={["btn btn-sm", if(@mode == :approved, do: "btn-primary", else: "btn-ghost")]}
          >
            Approved
          </.link>
        </div>

        <%= if @scenes == [] do %>
          <p class="text-base-content/60 text-sm">No scenes yet.</p>
        <% else %>
          <div class="space-y-4">
            <%= for {position, script_view, pieces} <- @scenes do %>
              <% visible = visible_pieces(script_view, pieces, @mode) %>
              <div class="card bg-base-200 shadow-sm">
                <div class="card-body py-4 space-y-3">
                  <div class="flex items-center gap-2">
                    <span class="badge badge-outline badge-sm font-mono">
                      #{position}
                    </span>
                    <h3 class="font-semibold">{script_view.title}</h3>
                    <%= if length(pieces) > 1 do %>
                      <.link
                        navigate={~p"/stories/#{@story.id}/scenes/#{script_view.id}/compare"}
                        class="ml-auto text-sm text-base-content/60 hover:text-base-content"
                      >
                        Compare →
                      </.link>
                    <% end %>
                  </div>

                  <%= if visible == [] do %>
                    <p class="text-base-content/50 text-sm">
                      <%= if @mode == :approved do %>
                        No approved version.
                      <% else %>
                        No versions yet.
                      <% end %>
                    </p>
                  <% else %>
                    <%= for piece <- visible do %>
                      <% rs = review_status(piece.weights, @story.through_lines) %>
                      <div class={[
                        "rounded p-2 text-sm",
                        if(piece.id == script_view.approved_version_id, do: "bg-base-300", else: ""),
                        if(rs == :unreviewed, do: "ring-2 ring-warning", else: "")
                      ]}>
                        <div class="flex flex-wrap items-center gap-2">
                          <span class="font-mono font-semibold">v{piece.version_number}</span>

                          <%= if piece.id == script_view.approved_version_id do %>
                            <span class="badge badge-success badge-sm">Approved</span>
                          <% end %>

                          <span class={[
                            "badge badge-sm",
                            if(piece.upstream_status == :stale,
                              do: "badge-warning",
                              else: "badge-ghost"
                            )
                          ]}>
                            {piece.upstream_status}
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
                              phx-value-version-id={piece.id}
                            >
                              Review
                            </button>

                            <%= if piece.id != script_view.approved_version_id do %>
                              <button
                                class="btn btn-xs btn-outline"
                                phx-click="approve_version"
                                phx-value-piece-id={script_view.id}
                                phx-value-version-id={piece.id}
                              >
                                Approve
                              </button>
                            <% end %>
                          </div>
                        </div>

                        <%= if MapSet.member?(@weight_forms, piece.id) do %>
                          <.weight_form version={piece} through_lines={@story.through_lines} />
                        <% end %>

                        <%= if Map.get(@content, piece.id) do %>
                          <pre class="mt-2 text-sm whitespace-pre-wrap font-mono bg-base-300 rounded p-3 leading-relaxed overflow-x-auto">{Map.get(@content, piece.id)}</pre>
                        <% end %>
                      </div>
                    <% end %>
                  <% end %>
                </div>
              </div>
            <% end %>
          </div>
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

  defp load_scenes(treatment_view) do
    tvscenes =
      Storybox.Stories.TreatmentViewScene
      |> Ash.Query.filter(treatment_view_id == ^treatment_view.id)
      |> Ash.Query.sort(position: :asc)
      |> Ash.read!(authorize?: false)

    scene_ids = Enum.map(tvscenes, & &1.scene_id)

    case scene_ids do
      [] ->
        []

      ids ->
        script_views =
          Storybox.Stories.ScriptView
          |> Ash.Query.filter(scene_id in ^ids)
          |> Ash.read!(authorize?: false)

        script_views_by_scene = Map.new(script_views, &{&1.scene_id, &1})
        view_ids = Enum.map(script_views, & &1.id)

        pieces_by_view =
          case view_ids do
            [] ->
              %{}

            vids ->
              Storybox.Stories.ScriptPiece
              |> Ash.Query.filter(script_view_id in ^vids)
              |> Ash.Query.sort(version_number: :desc)
              |> Ash.read!(authorize?: false)
              |> Enum.group_by(& &1.script_view_id)
          end

        tvscenes
        |> Enum.flat_map(fn tvs ->
          case script_views_by_scene[tvs.scene_id] do
            nil -> []
            sv -> [{tvs.position, sv, Map.get(pieces_by_view, sv.id, [])}]
          end
        end)
    end
  end

  defp fetch_visible_content(scenes, mode) do
    scenes
    |> Enum.flat_map(fn {_position, script_view, pieces} ->
      visible_pieces(script_view, pieces, mode)
    end)
    |> Enum.map(fn piece ->
      content =
        case Storybox.Storage.get_content(piece.content_uri) do
          {:ok, text} -> text
          _ -> nil
        end

      {piece.id, content}
    end)
    |> Map.new()
  end

  defp visible_pieces(_script_view, pieces, :latest) do
    case pieces do
      [] -> []
      [latest | _] -> [latest]
    end
  end

  defp visible_pieces(script_view, pieces, :approved) do
    Enum.filter(pieces, &(&1.id == script_view.approved_version_id))
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
