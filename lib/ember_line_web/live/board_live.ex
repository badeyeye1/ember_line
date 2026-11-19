defmodule EmberLineWeb.BoardLive do
  @moduledoc """
  Screen board, the intake panel only (slice load-prototype): drop or choose
  a prototype's files, or paste its HTML. The rest of the board (screens,
  timeline, slices, the code banner, Derive model) belongs to other slices.
  """
  use EmberLineWeb, :live_view

  alias EmberLine.Accounts.Workspace
  alias EmberLine.Modeling.{Errors, Intake, Prototypes}
  alias EmberLine.Modeling.Projections.ProjectList

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

        assign(socket, error: nil, notes: notes)

      {:error, reason} ->
        assign(socket, error: Errors.message(reason), notes: [])
    end
  end

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
          </div>
        </section>

        <.notice :if={@error} tone="err" id="intake-error">{@error}</.notice>
        <.notice :for={{note, i} <- Enum.with_index(@notes)} id={"intake-note-#{i}"}>{note}</.notice>
      </section>
    </Layouts.app>
    """
  end
end
