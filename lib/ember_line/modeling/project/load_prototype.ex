defmodule EmberLine.Modeling.Project.LoadPrototype do
  @moduledoc """
  Command LoadPrototype (slice load-prototype).

  Fields are the model's, plus `loaded_at`: time arrives in the command, so
  the aggregate never reads the clock. `EmberLine.Modeling.Intake` works out
  the file fields from the dropped or pasted files before dispatch.
  """

  @type t :: %__MODULE__{
          prototype_id: Ecto.UUID.t(),
          project_id: Ecto.UUID.t(),
          source: :files | :paste,
          file_names: [String.t()],
          unreadable_file_names: [String.t()],
          ignored_file_names: [String.t()],
          interactive: boolean(),
          too_large_file_names: [String.t()],
          total_bytes: non_neg_integer(),
          loaded_by: Ecto.UUID.t() | nil,
          loaded_at: DateTime.t()
        }

  defstruct [
    :prototype_id,
    :project_id,
    :loaded_by,
    :loaded_at,
    source: :files,
    file_names: [],
    unreadable_file_names: [],
    ignored_file_names: [],
    interactive: false,
    too_large_file_names: [],
    total_bytes: 0
  ]
end
