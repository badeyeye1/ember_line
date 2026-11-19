defmodule EmberLine.Modeling.Project do
  @moduledoc """
  The Project aggregate: decides (`execute/2`) and records (`apply/2`) for the
  Project stream. No database, clock or service calls; time and ids arrive in
  the command.
  """

  alias EmberLine.Accounts.Workspace
  alias EmberLine.Modeling.Project.{CreateProject, DeleteProject, ProjectCreated, ProjectDeleted}

  @source_types [:new, :local, :github]

  defstruct [:project_id, :name, deleted?: false]

  @type t :: %__MODULE__{
          project_id: Ecto.UUID.t() | nil,
          name: String.t() | nil,
          deleted?: boolean()
        }

  # create-project

  # A repeated CreateProject for a project that exists (a double submit) records nothing.
  def execute(%__MODULE__{project_id: id}, %CreateProject{}) when not is_nil(id), do: []

  def execute(%__MODULE__{}, %CreateProject{} = command) do
    cond do
      # Until Member roles exist, "allowed" means signed in.
      is_nil(command.created_by) ->
        {:error, :not_allowed}

      blank?(command.name) ->
        {:error, :project_name_required}

      command.source_type not in @source_types ->
        {:error, :source_type_not_listed}

      command.source_type == :github and blank?(command.repo_url) ->
        {:error, :repo_url_required}

      # Optional ("GitHub project with branch" has none), but one of the listed stacks if given.
      not (is_nil(command.stack) or command.stack in Workspace.stacks()) ->
        {:error, :stack_not_listed}

      true ->
        project_created(command)
    end
  end

  # delete-project

  def execute(%__MODULE__{} = project, %DeleteProject{} = command) do
    cond do
      is_nil(project.project_id) or project.deleted? -> {:error, :project_not_found}
      # Until Member roles exist, "allowed" means signed in.
      is_nil(command.deleted_by) -> {:error, :delete_not_allowed}
      command.confirmed != true -> {:error, {:confirm_delete, project.name}}
      true -> project_deleted(command)
    end
  end

  def apply(%__MODULE__{} = project, %ProjectCreated{project_id: id, name: name}),
    do: %{project | project_id: id, name: name}

  def apply(%__MODULE__{} = project, %ProjectDeleted{}), do: %{project | deleted?: true}

  defp project_created(%CreateProject{} = command) do
    %ProjectCreated{
      project_id: command.project_id,
      name: String.trim(command.name),
      description: command.description,
      source_type: command.source_type,
      folder_path: command.folder_path,
      repo_url: command.repo_url,
      branch: command.branch,
      stack: command.stack,
      persistence_mode: command.persistence_mode,
      created_at: command.created_at,
      created_by: command.created_by,
      workspace_id: command.workspace_id
    }
  end

  defp project_deleted(%DeleteProject{} = command) do
    %ProjectDeleted{
      project_id: command.project_id,
      deleted_by: command.deleted_by,
      deleted_at: command.deleted_at
    }
  end

  defp blank?(value), do: is_nil(value) or String.trim(value) == ""
end
