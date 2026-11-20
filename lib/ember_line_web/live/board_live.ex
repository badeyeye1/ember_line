defmodule EmberLineWeb.BoardLive do
  @moduledoc """
  Screen board, the intake panel only: drop or choose a prototype's files,
  or paste its HTML (slice load-prototype), then Split into pages (slice
  split-pages) and Undo split (slice undo-split).

  Split into pages and Undo split show for an interactive prototype loaded on this visit.
  Until view-intake's read model exists, the board can't tell which
  prototype a project has after a reload. The rest of the board (screens,
  timeline, slices, the code banner, Derive model) belongs to other slices.
  """
  use EmberLineWeb, :live_view

  alias EmberLine.Accounts.Workspace
  alias EmberLine.Modeling.{Errors, Intake, Prototypes}
  alias EmberLine.Modeling.Project
  alias EmberLine.Modeling.Projections.ProjectList
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
       |> assign(error: nil, notes: [], paste: to_form(%{"html" => ""}, as: :paste))
       |> assign(loaded: nil, pages: [])
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
      {:ok, split} ->
        {:noreply,
         socket
         |> assign(error: nil, notes: [Prototypes.split_note(loaded.file_name, split)])
         |> assign(loaded: %{loaded | split?: true})}

      # Split elsewhere: offer Undo split here too.
      {:error, :already_split = reason} ->
        {:noreply,
         assign(socket,
           error: Errors.message(reason),
           notes: [],
           loaded: %{loaded | split?: true}
         )}

      {:error, reason} ->
        {:noreply, assign(socket, error: Errors.message(reason), notes: [])}
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
        {:noreply,
         assign(socket,
           error: nil,
           notes: [Prototypes.undo_note(loaded.file_name)],
           loaded: %{loaded | split?: false}
         )}

      {:error, reason} ->
        {:noreply, assign(socket, error: Errors.message(reason), notes: [])}
    end
  end

  def handle_event("undo_split", _params, socket), do: {:noreply, socket}

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
      {:ok, loaded} ->
        notes =
          Enum.reject(
            [
              Intake.skipped_note(loaded.file_count, loaded.skipped_count),
              Intake.ignored_note(loaded.ignored_file_names)
            ],
            &is_nil/1
          )

        assign(socket,
          error: nil,
          notes: notes,
          pages: [],
          loaded: loaded_prototype(loaded, intake)
        )

      {:error, reason} ->
        assign(socket, error: Errors.message(reason), notes: [])
    end
  end

  # The loaded prototype, for Split into pages: its one file when it has one.
  defp loaded_prototype(loaded, %{file_names: [file_name], interactive: true}) do
    %{
      prototype_id: loaded.prototype_id,
      file_name: file_name,
      split?: false,
      src: ~p"/prototype/#{PrototypeController.token(loaded.prototype_id, file_name)}"
    }
  end

  defp loaded_prototype(_loaded, _intake), do: nil

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
