defmodule EmberLine.Modeling.Project do
  @moduledoc """
  The Project aggregate: decides (`execute/2`) and records (`apply/2`) for the
  Project stream. No database, clock or service calls; time and ids arrive in
  the command.
  """

  alias EmberLine.Accounts.Workspace

  alias EmberLine.Modeling.Project.{
    CreateProject,
    DeleteProject,
    LoadPrototype,
    ProjectCreated,
    ProjectDeleted,
    PrototypeLimits,
    PrototypeLoaded,
    PrototypeSplitIntoPages,
    SplitPrototype,
    SplitUndone
  }

  @source_types [:new, :local, :github]

  @max_pages 80

  defstruct [
    :project_id,
    :name,
    :prototype_id,
    deleted?: false,
    interactive?: false,
    split?: false
  ]

  @type t :: %__MODULE__{
          project_id: Ecto.UUID.t() | nil,
          name: String.t() | nil,
          prototype_id: Ecto.UUID.t() | nil,
          deleted?: boolean(),
          interactive?: boolean(),
          split?: boolean()
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

  # load-prototype

  def execute(%__MODULE__{} = project, %LoadPrototype{} = command) do
    cond do
      is_nil(project.project_id) or project.deleted? ->
        {:error, :project_not_found}

      # Until Member roles exist, "allowed" means signed in.
      is_nil(command.loaded_by) ->
        {:error, :load_not_allowed}

      command.unreadable_file_names != [] ->
        {:error, {:files_unreadable, command.unreadable_file_names}}

      command.too_large_file_names != [] ->
        {:error, {:files_too_large, command.too_large_file_names}}

      command.total_bytes > PrototypeLimits.max_total_bytes() ->
        {:error, :too_much_in_one_load}

      command.file_names == [] ->
        {:error, :no_usable_screens}

      true ->
        prototype_loaded(project, command)
    end
  end

  # split-pages

  def execute(%__MODULE__{} = project, %SplitPrototype{} = command) do
    cond do
      is_nil(project.project_id) or project.deleted? -> {:error, :project_not_found}
      # Until Member roles exist, "allowed" means signed in.
      is_nil(command.split_by) -> {:error, :split_not_allowed}
      not project.interactive? -> {:error, :not_interactive}
      project.split? -> {:error, :already_split}
      true -> split_found_pages(project, command)
    end
  end

  defp split_found_pages(_project, %SplitPrototype{found_page_count: 0, timed_out: true}),
    do: {:error, :prototype_did_not_respond}

  defp split_found_pages(_project, %SplitPrototype{found_page_count: 0}),
    do: {:error, :no_pages_found}

  defp split_found_pages(project, command), do: prototype_split_into_pages(project, command)

  def apply(%__MODULE__{} = project, %ProjectCreated{project_id: id, name: name}),
    do: %{project | project_id: id, name: name}

  def apply(%__MODULE__{} = project, %ProjectDeleted{}), do: %{project | deleted?: true}

  # A prototype loaded again keeps its id.
  # A new load clears the split.
  def apply(%__MODULE__{} = project, %PrototypeLoaded{} = event) do
    %{
      project
      | project_id: event.project_id,
        prototype_id: event.prototype_id,
        interactive?: event.interactive == true,
        split?: false
    }
  end

  def apply(%__MODULE__{} = project, %PrototypeSplitIntoPages{}), do: %{project | split?: true}
  def apply(%__MODULE__{} = project, %SplitUndone{}), do: %{project | split?: false}

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

  defp prototype_loaded(project, %LoadPrototype{} = command) do
    {file_names, skipped_count} = PrototypeLimits.kept(command.file_names)

    %PrototypeLoaded{
      prototype_id: project.prototype_id || command.prototype_id,
      project_id: command.project_id,
      source: command.source,
      file_names: file_names,
      file_count: length(file_names),
      skipped_count: skipped_count,
      ignored_file_names: command.ignored_file_names,
      interactive: command.interactive,
      loaded_by: command.loaded_by,
      loaded_at: command.loaded_at
    }
  end

  # The first 80 pages in the order found are kept.
  defp prototype_split_into_pages(project, %SplitPrototype{} = command) do
    page_count = min(command.found_page_count, @max_pages)

    %PrototypeSplitIntoPages{
      project_id: project.project_id,
      prototype_id: project.prototype_id,
      page_count: page_count,
      role_count: command.role_count,
      skipped_count: command.found_page_count - page_count,
      timed_out: command.timed_out,
      split_by: command.split_by,
      split_at: command.split_at
    }
  end

  @doc "How many of a split's pages are kept."
  def max_pages, do: @max_pages

  defp blank?(value), do: is_nil(value) or String.trim(value) == ""
end
