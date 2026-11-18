defmodule EmberLine.Modeling.Project.CreateProject do
  @moduledoc """
  Command CreateProject (slice create-project).

  Fields are the model's, plus `created_at`: time arrives in the command, so
  the aggregate never reads the clock.
  """

  @type source_type :: :new | :local | :github
  @type persistence_mode :: :event_sourced | :state_stored | :mixed

  @type t :: %__MODULE__{
          project_id: Ecto.UUID.t(),
          name: String.t() | nil,
          description: String.t() | nil,
          source_type: source_type() | nil,
          folder_path: String.t() | nil,
          repo_url: String.t() | nil,
          branch: String.t() | nil,
          stack: String.t() | nil,
          persistence_mode: persistence_mode() | nil,
          created_by: Ecto.UUID.t() | nil,
          workspace_id: Ecto.UUID.t(),
          created_at: DateTime.t()
        }

  defstruct [
    :project_id,
    :name,
    :description,
    :source_type,
    :folder_path,
    :repo_url,
    :branch,
    :stack,
    :persistence_mode,
    :created_by,
    :workspace_id,
    :created_at
  ]
end
