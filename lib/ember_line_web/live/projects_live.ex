defmodule EmberLineWeb.ProjectsLive do
  @moduledoc """
  Screen projects: the workspace's project list (read model ProjectList,
  slice view-projects) and the Create project form (slice create-project).
  """
  use EmberLineWeb, :live_view

  alias EmberLine.CommandedApp
  alias EmberLine.Modeling.Errors
  alias EmberLine.Modeling.Project.CreateProject
  alias EmberLine.Modeling.Projections.ProjectList

  on_mount {EmberLineWeb.LiveUserAuth, :live_user_required}

  # Wording from docs/design/screens/projects.html.
  @source_types [
    {"Start fresh", "new"},
    {"Codebase on this computer", "local"},
    {"GitHub repository", "github"}
  ]
  @stacks [
    "Elixir: Phoenix LiveView + Ash + AshCommanded",
    "Elixir: Phoenix LiveView + Ash",
    "Elixir: Phoenix LiveView + Ash + Commanded",
    "Elixir: Phoenix LiveView + Ash + Commanded + Hologram",
    "Elixir: Phoenix LiveView + Ash + Commanded + Elm",
    "Elixir: Phoenix LiveView + Commanded",
    "Other"
  ]
  @persistence_modes [
    {"Event sourced: events are the source of truth", "event_sourced"},
    {"State stored (CRUD): tables hold current state; events are the changes", "state_stored"},
    {"Mixed: choose per stream later", "mixed"}
  ]
  @new_form %{
    "source_type" => "new",
    "branch" => "main",
    "stack" => "Elixir: Phoenix LiveView + Ash + AshCommanded",
    "persistence_mode" => "event_sourced"
  }
  @source_type_values %{"new" => :new, "local" => :local, "github" => :github}
  @persistence_mode_values %{
    "event_sourced" => :event_sourced,
    "state_stored" => :state_stored,
    "mixed" => :mixed
  }

  @impl true
  def mount(%{"workspace_id" => workspace_id}, _session, socket) do
    case Ecto.UUID.cast(workspace_id) do
      {:ok, workspace_id} ->
        {:ok,
         socket
         |> assign(page_title: "Projects", workspace_id: workspace_id, error: nil)
         |> assign_projects()
         |> assign_form(@new_form)}

      :error ->
        {:ok,
         socket |> put_flash(:error, "That workspace doesn't exist.") |> push_navigate(to: ~p"/")}
    end
  end

  @impl true
  def handle_event("change", %{"project" => params}, socket) do
    {:noreply, assign_form(socket, params)}
  end

  def handle_event("create", %{"project" => params}, socket) do
    command = %CreateProject{
      project_id: Ecto.UUID.generate(),
      name: params["name"],
      description: present(params["description"]),
      source_type: Map.get(@source_type_values, params["source_type"]),
      folder_path: present(params["folder_path"]),
      repo_url: present(params["repo_url"]),
      branch: present(params["branch"]),
      stack: present(params["stack"]),
      persistence_mode: Map.get(@persistence_mode_values, params["persistence_mode"]),
      created_by: socket.assigns.current_user.id,
      workspace_id: socket.assigns.workspace_id,
      created_at: DateTime.utc_now() |> DateTime.truncate(:second)
    }

    case CommandedApp.dispatch(command, consistency: :strong) do
      :ok ->
        {:noreply,
         socket
         |> assign(error: nil)
         |> assign_projects()
         |> assign_form(@new_form)
         |> put_flash(:info, "Project created.")}

      {:error, reason} ->
        {:noreply, socket |> assign(error: Errors.message(reason)) |> assign_form(params)}
    end
  end

  defp assign_projects(socket) do
    assign(socket, projects: ProjectList.for_workspace!(socket.assigns.workspace_id))
  end

  defp assign_form(socket, params), do: assign(socket, form: to_form(params, as: :project))

  defp present(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp present(_value), do: nil

  defp label_for(options, value) do
    Enum.find_value(options, fn {label, v} -> if v == to_string(value), do: label end)
  end

  @impl true
  def render(assigns) do
    assigns =
      assign(assigns,
        source_types: @source_types,
        stacks: @stacks,
        persistence_modes: @persistence_modes,
        source: assigns.form[:source_type].value
      )

    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      workspace={%{id: @workspace_id}}
      nav={:projects}
      crumbs={[{"Projects", nil}]}
    >
      <section class="ui-page" aria-label="Projects">
        <.page_header
          title="Projects"
          description="A project holds one event model. Start fresh, or point it at an existing codebase so the board starts from what's already built."
        />

        <div class="grid items-start gap-4 lg:grid-cols-[minmax(0,440px)_minmax(0,1fr)]">
          <.card>
            <.form
              for={@form}
              id="new-project-form"
              class="grid gap-2.5 p-4 [&_.ui-fld]:text-muted"
              phx-change="change"
              phx-submit="create"
            >
              <h2 class="text-base font-semibold">New project</h2>
              <.segmented field={@form[:source_type]} label="Start from" options={@source_types} />
              <.field
                field={@form[:name]}
                label="Project name"
                placeholder="e.g. Edgemastery"
                autocomplete="off"
              />
              <.field
                field={@form[:description]}
                type="textarea"
                label="What it is (optional)"
                rows="2"
                placeholder="One line on what the app does"
              />
              <.subsection :if={@source == "local"}>
                <.field
                  field={@form[:folder_path]}
                  label="Folder path"
                  placeholder="~/code/edgemastery"
                  autocomplete="off"
                />
              </.subsection>
              <.subsection :if={@source == "github"}>
                <.field
                  field={@form[:repo_url]}
                  label="Repository URL"
                  placeholder="https://github.com/acme/edgemastery"
                  autocomplete="off"
                />
                <.field field={@form[:branch]} label="Branch" autocomplete="off" />
              </.subsection>
              <.field
                field={@form[:stack]}
                type="select"
                label="Stack"
                options={Enum.map(@stacks, &{&1, &1})}
              />
              <.field
                field={@form[:persistence_mode]}
                type="select"
                label="How it stores data"
                options={@persistence_modes}
                hint="Event Modeling works either way. Existing codebases are usually state stored."
              />
              <.notice :if={@error} tone="err">{@error}</.notice>
              <div>
                <.button variant="primary" type="submit" phx-disable-with="Creating…">
                  Create project
                </.button>
              </div>
            </.form>
          </.card>

          <div :if={@projects != []} id="projects" class="grid gap-2.5">
            <.card :for={project <- @projects} id={"project-#{project.project_id}"}>
              <div class="grid gap-2 p-3.5">
                <h3 class="text-[17px] font-semibold">
                  {project.name}<span :if={project.is_sample}> (sample)</span>
                </h3>
                <p :if={project.description} class="m-0">{project.description}</p>
                <p class="m-0 flex flex-wrap gap-x-3.5 gap-y-1.5 text-[12.5px] text-muted">
                  <span>{label_for(@source_types, project.source_type)}</span>
                  <span :if={project.stack}>{project.stack}</span>
                  <span :if={project.persistence_mode}>
                    {label_for(@persistence_modes, project.persistence_mode) |> short_mode()}
                  </span>
                  <span>Created {Calendar.strftime(project.created_at, "%-d %b %Y")}</span>
                </p>
              </div>
            </.card>
          </div>
        </div>
      </section>
    </Layouts.app>
    """
  end

  defp short_mode(label), do: label |> String.split(":") |> hd()
end
