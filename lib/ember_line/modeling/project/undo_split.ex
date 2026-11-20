defmodule EmberLine.Modeling.Project.UndoSplit do
  @moduledoc """
  Command UndoSplit (slice undo-split): back to the loaded file after a
  split. Fields are the model's, plus `undone_at`: time arrives in the
  command.
  """

  @type t :: %__MODULE__{
          project_id: Ecto.UUID.t(),
          prototype_id: Ecto.UUID.t(),
          undone_by: Ecto.UUID.t() | nil,
          undone_at: DateTime.t()
        }

  defstruct [:project_id, :prototype_id, :undone_by, :undone_at]
end
