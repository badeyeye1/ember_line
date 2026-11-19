defmodule EmberLine.Modeling.Project.DeleteProject do
  @moduledoc """
  Command DeleteProject (slice delete-project).

  Fields are the model's, plus `deleted_at`: time arrives in the command, so
  the aggregate never reads the clock.
  """

  @type t :: %__MODULE__{
          project_id: Ecto.UUID.t(),
          deleted_by: Ecto.UUID.t() | nil,
          confirmed: boolean(),
          deleted_at: DateTime.t()
        }

  defstruct [:project_id, :deleted_by, :deleted_at, confirmed: false]
end
