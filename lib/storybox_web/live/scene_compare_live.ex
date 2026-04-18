defmodule StoryboxWeb.SceneCompareLive do
  use StoryboxWeb, :live_view

  require Ash.Query

  @impl true
  def mount(%{"story_id" => story_id, "scene_id" => scene_id}, _session, socket) do
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
            scene =
              Storybox.Stories.ScenePiece
              |> Ash.Query.filter(id == ^scene_id)
              |> Ash.read_one!(authorize?: false)

            case scene do
              nil ->
                {:ok,
                 socket
                 |> put_flash(:error, "Scene not found.")
                 |> redirect(to: ~p"/")}

              scene ->
                sequence =
                  Storybox.Stories.SequencePiece
                  |> Ash.Query.filter(id == ^scene.sequence_piece_id and story_id == ^story.id)
                  |> Ash.read_one!(authorize?: false)

                case sequence do
                  nil ->
                    {:ok,
                     socket
                     |> put_flash(:error, "Scene not found.")
                     |> redirect(to: ~p"/")}

                  sequence ->
                    versions = load_versions(scene)

                    {:ok,
                     socket
                     |> assign(:story, story)
                     |> assign(:sequence, sequence)
                     |> assign(:scene, scene)
                     |> assign(:versions, versions)
                     |> assign(:left_version, nil)
                     |> assign(:right_version, nil)
                     |> assign(:left_content, nil)
                     |> assign(:right_content, nil)
                     |> assign(:weight_forms, MapSet.new())
                     |> assign(:page_title, "#{story.title} — #{scene.title} Compare")}
                end
            end
        end
    end
  end

  @impl true
  def handle_params(params, _uri, socket) do
    versions = socket.assigns.versions

    right_version =
      case parse_version_number(params["right"]) do
        nil -> default_right(versions)
        n -> find_version(versions, n) || default_right(versions)
      end

    left_version =
      case parse_version_number(params["left"]) do
        nil -> default_left(versions)
        n -> find_version(versions, n) || default_left(versions)
      end

    {:noreply,
     socket
     |> assign(:left_version, left_version)
     |> assign(:right_version, right_version)
     |> assign(:left_content, fetch_content(left_version))
     |> assign(:right_content, fetch_content(right_version))}
  end

  @impl true
  def handle_event("approve_version", %{"version-id" => version_id}, socket) do
    socket.assigns.scene
    |> Ash.Changeset.for_update(:approve_version, %{version_id: version_id})
    |> Ash.update!(authorize?: false)

    scene =
      Storybox.Stories.ScenePiece
      |> Ash.Query.filter(id == ^socket.assigns.scene.id)
      |> Ash.read_one!(authorize?: false)

    versions = load_versions(scene)

    left_version =
      if socket.assigns.left_version,
        do: find_version(versions, socket.assigns.left_version.version_number),
        else: nil

    right_version =
      if socket.assigns.right_version,
        do: find_version(versions, socket.assigns.right_version.version_number),
        else: nil

    {:noreply,
     socket
     |> assign(:scene, scene)
     |> assign(:versions, versions)
     |> assign(:left_version, left_version)
     |> assign(:right_version, right_version)}
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
      Storybox.Stories.SceneVersion
      |> Ash.Query.filter(id == ^version_id)
      |> Ash.read_one!(authorize?: false)

    version
    |> Ash.Changeset.for_update(:set_weights, %{weights: weights})
    |> Ash.update!(authorize?: false)

    versions = load_versions(socket.assigns.scene)
    weight_forms = MapSet.delete(socket.assigns.weight_forms, version_id)

    left_version =
      if socket.assigns.left_version,
        do: find_version(versions, socket.assigns.left_version.version_number),
        else: nil

    right_version =
      if socket.assigns.right_version,
        do: find_version(versions, socket.assigns.right_version.version_number),
        else: nil

    {:noreply,
     socket
     |> assign(:versions, versions)
     |> assign(:left_version, left_version)
     |> assign(:right_version, right_version)
     |> assign(:weight_forms, weight_forms)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div class="space-y-6">
        <nav class="flex items-center gap-2 text-sm text-base-content/60">
          <.link navigate={~p"/stories/#{@story.id}/treatment"} class="hover:text-base-content">
            {@story.title}
          </.link>
          <span>›</span>
          <.link
            navigate={~p"/stories/#{@story.id}/sequences/#{@sequence.id}/script"}
            class="hover:text-base-content"
          >
            {@sequence.title} Script
          </.link>
          <span>›</span>
          <span class="text-base-content">{@scene.title} Compare</span>
        </nav>

        <h1 class="text-2xl font-bold">{@scene.title} — Version Comparison</h1>

        <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
          <div class="space-y-3">
            <div class="flex flex-wrap items-center gap-1">
              <span class="text-xs text-base-content/50 mr-1">Left:</span>
              <%= for v <- @versions do %>
                <.link
                  patch={
                    build_compare_path(
                      @story.id,
                      @scene.id,
                      v.version_number,
                      version_num(@right_version)
                    )
                  }
                  class={[
                    "btn btn-xs",
                    if(@left_version && @left_version.id == v.id,
                      do: "btn-primary",
                      else: "btn-ghost"
                    )
                  ]}
                >
                  v{v.version_number}
                </.link>
              <% end %>
            </div>

            <%= if @left_version do %>
              <% rs = review_status(@left_version.weights, @story.through_lines) %>
              <div class={[
                "rounded p-2 text-sm",
                if(@left_version.id == @scene.approved_version_id, do: "bg-base-200", else: ""),
                if(rs == :unreviewed, do: "ring-2 ring-warning", else: "")
              ]}>
                <div class="flex flex-wrap items-center gap-2">
                  <span class="font-mono font-semibold">v{@left_version.version_number}</span>

                  <%= if @left_version.id == @scene.approved_version_id do %>
                    <span class="badge badge-success badge-sm">Approved</span>
                  <% end %>

                  <span class={[
                    "badge badge-sm",
                    if(@left_version.upstream_status == :stale,
                      do: "badge-warning",
                      else: "badge-ghost"
                    )
                  ]}>
                    {@left_version.upstream_status}
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
                      phx-value-version-id={@left_version.id}
                    >
                      Review
                    </button>

                    <%= if @left_version.id != @scene.approved_version_id do %>
                      <button
                        class="btn btn-xs btn-outline"
                        phx-click="approve_version"
                        phx-value-version-id={@left_version.id}
                      >
                        Approve
                      </button>
                    <% end %>
                  </div>
                </div>

                <%= if MapSet.member?(@weight_forms, @left_version.id) do %>
                  <.weight_form version={@left_version} through_lines={@story.through_lines} />
                <% end %>
              </div>

              <%= if @left_content do %>
                <pre class="text-sm whitespace-pre-wrap font-mono bg-base-300 rounded p-3 leading-relaxed overflow-x-auto">{@left_content}</pre>
              <% end %>
            <% else %>
              <div class="rounded p-4 bg-base-200 text-base-content/50 text-sm text-center">
                No version selected
              </div>
            <% end %>
          </div>

          <div class="space-y-3">
            <div class="flex flex-wrap items-center gap-1">
              <span class="text-xs text-base-content/50 mr-1">Right:</span>
              <%= for v <- @versions do %>
                <.link
                  patch={
                    build_compare_path(
                      @story.id,
                      @scene.id,
                      version_num(@left_version),
                      v.version_number
                    )
                  }
                  class={[
                    "btn btn-xs",
                    if(@right_version && @right_version.id == v.id,
                      do: "btn-primary",
                      else: "btn-ghost"
                    )
                  ]}
                >
                  v{v.version_number}
                </.link>
              <% end %>
            </div>

            <%= if @right_version do %>
              <% rs = review_status(@right_version.weights, @story.through_lines) %>
              <div class={[
                "rounded p-2 text-sm",
                if(@right_version.id == @scene.approved_version_id, do: "bg-base-200", else: ""),
                if(rs == :unreviewed, do: "ring-2 ring-warning", else: "")
              ]}>
                <div class="flex flex-wrap items-center gap-2">
                  <span class="font-mono font-semibold">v{@right_version.version_number}</span>

                  <%= if @right_version.id == @scene.approved_version_id do %>
                    <span class="badge badge-success badge-sm">Approved</span>
                  <% end %>

                  <span class={[
                    "badge badge-sm",
                    if(@right_version.upstream_status == :stale,
                      do: "badge-warning",
                      else: "badge-ghost"
                    )
                  ]}>
                    {@right_version.upstream_status}
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
                      phx-value-version-id={@right_version.id}
                    >
                      Review
                    </button>

                    <%= if @right_version.id != @scene.approved_version_id do %>
                      <button
                        class="btn btn-xs btn-outline"
                        phx-click="approve_version"
                        phx-value-version-id={@right_version.id}
                      >
                        Approve
                      </button>
                    <% end %>
                  </div>
                </div>

                <%= if MapSet.member?(@weight_forms, @right_version.id) do %>
                  <.weight_form version={@right_version} through_lines={@story.through_lines} />
                <% end %>
              </div>

              <%= if @right_content do %>
                <pre class="text-sm whitespace-pre-wrap font-mono bg-base-300 rounded p-3 leading-relaxed overflow-x-auto">{@right_content}</pre>
              <% end %>
            <% else %>
              <div class="rounded p-4 bg-base-200 text-base-content/50 text-sm text-center">
                No version selected
              </div>
            <% end %>
          </div>
        </div>
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

  defp load_versions(scene) do
    Storybox.Stories.SceneVersion
    |> Ash.Query.filter(scene_piece_id == ^scene.id)
    |> Ash.Query.sort(version_number: :desc)
    |> Ash.read!(authorize?: false)
  end

  defp find_version(_versions, nil), do: nil
  defp find_version(versions, number), do: Enum.find(versions, &(&1.version_number == number))

  defp default_right([]), do: nil
  defp default_right([latest | _]), do: latest

  defp default_left([]), do: nil
  defp default_left([_]), do: nil
  defp default_left([_, second | _]), do: second

  defp fetch_content(nil), do: nil

  defp fetch_content(version) do
    case Storybox.Storage.get_content(version.content_uri) do
      {:ok, text} -> text
      _ -> nil
    end
  end

  defp parse_version_number(nil), do: nil

  defp parse_version_number(s) do
    case Integer.parse(s) do
      {n, ""} -> n
      _ -> nil
    end
  end

  defp version_num(nil), do: nil
  defp version_num(version), do: version.version_number

  defp build_compare_path(story_id, scene_id, left_num, right_num) do
    base = "/stories/#{story_id}/scenes/#{scene_id}/compare"
    params = Enum.reject([left: left_num, right: right_num], fn {_, v} -> is_nil(v) end)
    if params == [], do: base, else: base <> "?" <> URI.encode_query(params)
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
