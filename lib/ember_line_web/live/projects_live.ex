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

  @source_types [
    {"Start fresh", "new"},
    {"Local folder", "local"},
    {"GitHub repository", "github"}
  ]
  @persistence_modes [
    {"Event sourced", "event_sourced"},
    {"State stored", "state_stored"},
    {"Mixed", "mixed"}
  ]
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
         |> assign_form(%{"source_type" => "new"})}

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
         |> assign_form(%{"source_type" => "new"})
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
      assign(assigns, source_types: @source_types, persistence_modes: @persistence_modes)

    ~H"""
    <Layouts.app flash={@flash}>
      <.header>Projects</.header>

      <ul :if={@projects != []} id="projects" class="space-y-3">
        <li :for={project <- @projects} id={"project-#{project.project_id}"} class="card bg-base-200">
          <div class="card-body p-4">
            <h2 class="card-title">
              {project.name}
              <span :if={project.is_sample} class="badge badge-neutral">Sample</span>
            </h2>
            <p :if={project.description}>{project.description}</p>
            <p class="text-sm opacity-70">
              {label_for(@source_types, project.source_type)}
              <span :if={project.stack}>· {project.stack}</span>
              <span :if={project.persistence_mode}>
                · {label_for(@persistence_modes, project.persistence_mode)}
              </span>
            </p>
          </div>
        </li>
      </ul>

      <.form for={@form} id="new-project-form" phx-change="change" phx-submit="create">
        <h2 class="text-lg font-semibold">New project</h2>
        <p :if={@error} class="alert alert-error" role="alert">{@error}</p>
        <.input field={@form[:name]} label="Name" />
        <.input field={@form[:description]} type="textarea" label="Description" />
        <.input field={@form[:source_type]} type="select" label="Starts from" options={@source_types} />
        <.input field={@form[:folder_path]} label="Folder path (local folder)" />
        <.input field={@form[:repo_url]} label="Repository URL (GitHub)" />
        <.input field={@form[:branch]} label="Branch (GitHub)" />
        <.input field={@form[:stack]} label="Stack" />
        <.input
          field={@form[:persistence_mode]}
          type="select"
          label="Storage"
          prompt="Not decided yet"
          options={@persistence_modes}
        />
        <.button variant="primary" phx-disable-with="Creating…">Create project</.button>
      </.form>
    </Layouts.app>
    """
  end
end
