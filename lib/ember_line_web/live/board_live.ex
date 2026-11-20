defmodule EmberLineWeb.BoardLive do
  @moduledoc """
  Screen board, the intake panel and the prototype's screens: drop or choose
  a prototype's files, or paste its HTML (slice load-prototype), then Split
  into pages (slice split-pages) and Undo split (slice undo-split). The
  screens show as tabs, with the notes, from the PrototypeScreens read model
  (slice view-intake), so they come back when the board opens again.

  The rest of the board (the summary, timeline, slices, the code banner,
  Derive model) belongs to other slices.
  """
  use EmberLineWeb, :live_view

  alias EmberLine.Accounts.Workspace
  alias EmberLine.Modeling.{Errors, Intake, Prototypes}
  alias EmberLine.Modeling.Project
  alias EmberLine.Modeling.Projections.{ProjectList, PrototypeScreens}
  alias EmberLineWeb.PrototypeController

  on_mount {EmberLineWeb.LiveUserAuth, :live_user_required}

  # Big enough that every file over 20 MB still arrives as an entry to name
  # in the "larger than 20 MB" sentence; larger ones are named from their size.
  @max_upload_bytes 101 * 1024 * 1024
  @max_entries 1000

  @impl true
  def mount(%{"workspace_id" => workspace_id, "project_id" => project_id}, _session, socket) do
    user = socket.assigns.current_user

    with {:ok, workspace} <- Ash.get(Workspace, workspace_id, actor: user),
         {:ok, project} <- Ash.get(ProjectList, project_id, authorize?: false),
         true <- project.workspace_id == workspace.id do
      {:ok,
       socket
       |> assign(page_title: project.name, workspace: workspace, project: project)
       |> assign(error: nil, paste: to_form(%{"html" => ""}, as: :paste), pages: [])
       |> show_screens()
       |> allow_upload(:prototype,
         accept: :any,
         max_entries: @max_entries,
         max_file_size: @max_upload_bytes,
         auto_upload: true,
         progress: &handle_progress/3
       )}
    else
      _missing ->
        {:ok,
         socket
         |> put_flash(:error, Errors.message(:project_not_found))
         |> push_navigate(to: ~p"/workspaces/#{workspace_id}/projects")}
    end
  end

  @impl true
  def handle_event("files", _params, socket), do: {:noreply, maybe_load_files(socket)}

  def handle_event("paste", %{"paste" => %{"html" => html}}, socket) do
    if String.trim(html) == "" do
      {:noreply, socket}
    else
      {:noreply,
       socket
       |> load(:paste, Intake.paste(html))
       |> assign(paste: to_form(%{"html" => html}, as: :paste))}
    end
  end

  # split-pages: the hook sends the pages it finds, then what it found in all.
  def handle_event("split_page", %{"title" => title, "html" => html} = page, socket) do
    if socket.assigns.loaded && length(socket.assigns.pages) < Project.max_pages() do
      page = %{title: title, role: page["role"], route: page["route"], html: html}
      {:noreply, update(socket, :pages, &(&1 ++ [page]))}
    else
      {:noreply, socket}
    end
  end

  def handle_event("split_done", params, %{assigns: %{loaded: %{} = loaded}} = socket) do
    result =
      Prototypes.split(
        socket.assigns.project.project_id,
        loaded.prototype_id,
        socket.assigns.pages,
        count(params["found"]),
        count(params["roles"]),
        params["timed_out"] == true,
        socket.assigns.current_user.id
      )

    socket = assign(socket, pages: [])

    case result do
      {:ok, _split} ->
        {:noreply, socket |> assign(error: nil) |> show_screens()}

      # Split elsewhere: the screens show it, and Undo split is offered with the error.
      {:error, reason} ->
        {:noreply, socket |> show_screens() |> assign(error: Errors.message(reason), notes: [])}
    end
  end

  def handle_event("split_done", _params, socket), do: {:noreply, socket}

  # undo-split
  def handle_event("undo_split", _params, %{assigns: %{loaded: %{} = loaded}} = socket) do
    case Prototypes.undo_split(
           socket.assigns.project.project_id,
           loaded.prototype_id,
           socket.assigns.current_user.id
         ) do
      {:ok, _undone} ->
        socket = socket |> assign(error: nil) |> show_screens()
        {:noreply, assign(socket, notes: [Prototypes.undo_note(socket.assigns.loaded.file_name)])}

      {:error, reason} ->
        {:noreply, socket |> show_screens() |> assign(error: Errors.message(reason), notes: [])}
    end
  end

  def handle_event("undo_split", _params, socket), do: {:noreply, socket}

  # view-intake: flip between the screens.
  def handle_event("show_tab", %{"position" => position}, socket) do
    case Enum.find(socket.assigns.screens.tabs, &("#{&1.position}" == position)) do
      nil -> {:noreply, socket}
      tab -> {:noreply, show_tab(socket, tab)}
    end
  end

  defp count(n) when is_integer(n) and n >= 0, do: n
  defp count(_not_a_count), do: 0

  defp handle_progress(:prototype, _entry, socket), do: {:noreply, maybe_load_files(socket)}

  # Loads once every chosen file has arrived (or was too big to send).
  # `path` is the temporary file LiveView wrote the upload to, not user input.
  # sobelow_skip ["Traversal.FileModule"]
  defp maybe_load_files(socket) do
    entries = socket.assigns.uploads.prototype.entries

    if entries != [] and Enum.all?(entries, &(&1.done? or not &1.valid?)) do
      refused = Enum.reject(entries, & &1.valid?)
      socket = Enum.reduce(refused, socket, &cancel_upload(&2, :prototype, &1.ref))

      read =
        socket
        |> consume_uploaded_entries(:prototype, fn %{path: path}, entry ->
          {:ok, {entry.ref, File.read!(path)}}
        end)
        |> Map.new()

      # In the order they were chosen; a file too big to send has no content.
      files =
        for e <- entries, do: %{name: e.client_name, size: e.client_size, content: read[e.ref]}

      load(socket, :files, Intake.read(files))
    else
      socket
    end
  end

  defp load(socket, source, intake) do
    case Prototypes.load(
           socket.assigns.project.project_id,
           source,
           intake,
           socket.assigns.current_user.id
         ) do
      {:ok, _loaded} ->
        socket |> assign(error: nil, pages: []) |> show_screens()

      {:error, reason} ->
        assign(socket, error: Errors.message(reason), notes: [])
    end
  end

  # view-intake: the screens and notes from the read model, on the first tab.
  defp show_screens(socket) do
    screens = PrototypeScreens.for_project!(socket.assigns.project.project_id)

    socket
    |> assign(screens: screens, notes: screens.notes, loaded: loaded_prototype(screens))
    |> show_tab(List.first(screens.tabs))
  end

  defp show_tab(socket, nil), do: assign(socket, tab: nil, tab_src: nil)

  defp show_tab(socket, tab) do
    prototype_id = socket.assigns.screens.prototype_id

    token =
      case tab.kind do
        :page -> PrototypeController.page_token(prototype_id, tab.source)
        _file -> PrototypeController.token(prototype_id, tab.source)
      end

    assign(socket, tab: tab, tab_src: ~p"/prototype/#{token}")
  end

  # The loaded prototype, for Split into pages and Undo split: an interactive
  # prototype's one file. While it's split, its tabs are the pages.
  defp loaded_prototype(%{interactive: true, file_count: 1, is_split: true} = screens),
    do: %{prototype_id: screens.prototype_id, file_name: nil, split?: true, src: nil}

  defp loaded_prototype(%{interactive: true, file_count: 1, tabs: [%{source: name}]} = screens) do
    %{
      prototype_id: screens.prototype_id,
      file_name: name,
      split?: false,
      src: ~p"/prototype/#{PrototypeController.token(screens.prototype_id, name)}"
    }
  end

  defp loaded_prototype(_screens), do: nil

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      workspace={%{id: @workspace.id, name: @workspace.name}}
      project={%{id: @project.project_id, name: @project.name}}
      nav={:board}
      crumbs={[{@project.name, ~p"/workspaces/#{@workspace.id}/projects"}, {"Board", nil}]}
    >
      <section class="ui-page grid gap-3" aria-label="Board">
        <section class="ui-intake" aria-label="Screen input">
          <form
            id="prototype-files"
            class="ui-drop"
            phx-change="files"
            phx-submit="files"
            phx-drop-target={@uploads.prototype.ref}
          >
            <p>
              <strong>Drop a whole prototype</strong>: one or more HTML files, a set of screenshots, or a .zip of the project. Claude finds every screen and models the full flow.
            </p>
            <label class="ui-btn">
              Choose files <.live_file_input upload={@uploads.prototype} class="hidden" />
            </label>
          </form>
          <div class="ui-intake-side">
            <.form for={@paste} id="prototype-paste" phx-change="paste" phx-submit="paste">
              <textarea
                id={@paste[:html].id}
                name={@paste[:html].name}
                class="ui-in ui-mono"
                phx-debounce="blur"
                aria-label="Prototype HTML"
                placeholder="…or paste the HTML of a Claude prototype"
              >{Phoenix.HTML.Form.normalize_value("textarea", @paste[:html].value)}</textarea>
            </.form>
            <div :if={@loaded && !@loaded.split?} class="flex flex-wrap gap-2">
              <.button
                id="split-pages"
                type="button"
                phx-hook=".Splitter"
                data-src={@loaded.src}
                title="Run the prototype, visit every page for every role, and turn each into its own HTML file"
              >
                Split into pages
              </.button>
            </div>
          </div>
        </section>

        <.notice :if={@error} tone="err" id="intake-error">
          {@error}<.undo_split :if={@loaded && @loaded.split?} />
        </.notice>
        <.notice :for={{note, i} <- Enum.with_index(@notes)} id={"intake-note-#{i}"}>
          {note}<.undo_split :if={@loaded && @loaded.split? && !@error && i == 0} />
        </.notice>

        <section class="ui-screen-band" aria-label="Prototype screens">
          <div class="ui-screen-col">
            <div
              :if={length(@screens.tabs) > 1}
              class="ui-screen-tabs"
              role="tablist"
              aria-label="Prototype files"
            >
              <button
                :for={tab <- @screens.tabs}
                type="button"
                role="tab"
                aria-selected={to_string(tab.position == @tab.position)}
                title={tab.label}
                phx-click="show_tab"
                phx-value-position={tab.position}
              >
                {tab.label}
              </button>
            </div>
            <div class="ui-screen-frame">
              <div class="bar">
                <i></i><i></i><i></i>
                <span id="screen-label">{screen_label(@screens.tabs, @tab)}</span>
              </div>
              <div class="ui-screen-view" id="screen-view">
                <.screen :if={@tab} tab={@tab} src={@tab_src} />
                <div :if={!@tab} class="ui-nomatch">
                  Drop the prototype above to see its screens here.
                </div>
              </div>
            </div>
          </div>
        </section>
      </section>
    </Layouts.app>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".Splitter">
      // Runs the loaded prototype in a hidden, sandboxed frame. The crawler in
      // it (priv/prototype/bridge.js) visits every role and page and posts each
      // page back; the first 80 go to the server, then the counts. It stops
      // after 4 minutes, keeping what it found.
      const MAX_PAGES = 80
      const TIME_LIMIT = 4 * 60 * 1000

      export default {
        mounted() {
          this.el.addEventListener("click", () => this.split())
        },
        destroyed() {
          this.stop?.()
        },
        split() {
          if (this.stop) return
          const box = document.createElement("div")
          box.className = "ui-offscreen"
          box.setAttribute("aria-hidden", "true")
          const frame = document.createElement("iframe")
          frame.setAttribute("sandbox", "allow-scripts")
          frame.tabIndex = -1
          frame.src = this.el.dataset.src
          box.append(frame)

          let found = 0
          const roles = new Set()
          const onMessage = (e) => {
            if (e.source !== frame.contentWindow) return
            const d = e.data || {}
            if (d.t === "em-ready") {
              frame.contentWindow.postMessage({t: "em-crawl", max: 1000}, "*")
            } else if (d.t === "em-page" && d.page) {
              found += 1
              if (d.page.role) roles.add(d.page.role)
              if (found <= MAX_PAGES) {
                const {title, role, route, html} = d.page
                this.pushEvent("split_page", {title: String(title || ""), role, route, html: String(html || "")})
              }
            } else if (d.t === "em-crawl-done") {
              finish(false)
            }
          }
          const timer = setTimeout(() => finish(true), TIME_LIMIT)
          this.stop = () => {
            clearTimeout(timer)
            window.removeEventListener("message", onMessage)
            box.remove()
            this.el.disabled = false
            this.el.removeAttribute("aria-busy")
            this.stop = null
          }
          const finish = (timedOut) => {
            this.stop()
            this.pushEvent("split_done", {found, roles: roles.size, timed_out: timedOut})
          }

          window.addEventListener("message", onMessage)
          this.el.disabled = true
          this.el.setAttribute("aria-busy", "true")
          document.body.append(box)
        }
      }
    </script>
    """
  end

  # view-intake: the frame's label, as in the prototype.
  defp screen_label(_tabs, nil), do: "No prototype yet"
  defp screen_label([_one], tab), do: tab.label

  defp screen_label(tabs, tab),
    do: "#{tab.label} · #{Enum.find_index(tabs, &(&1 == tab)) + 1} of #{length(tabs)}"

  # view-intake: screenshots as images; HTML files and pages sandboxed with
  # scripts off; an interactive prototype's file live, sandboxed.
  attr :tab, :map, required: true
  attr :src, :string, required: true

  defp screen(%{tab: %{kind: :image}} = assigns) do
    ~H"""
    <img src={@src} alt={@tab.label} />
    """
  end

  defp screen(%{tab: %{kind: :live_html}} = assigns) do
    ~H"""
    <iframe id={"screen-#{@tab.position}"} src={@src} title={@tab.label} sandbox="allow-scripts"></iframe>
    """
  end

  defp screen(assigns) do
    ~H"""
    <iframe id={"screen-#{@tab.position}"} src={@src} title={@tab.label} sandbox=""></iframe>
    """
  end

  # undo-split: next to the split sentence, as in the prototype.
  defp undo_split(assigns) do
    ~H"""
    <span class="ui-split-actions">
      <.button id="undo-split" type="button" size="small" phx-click="undo_split">
        Undo split
      </.button>
    </span>
    """
  end
end
