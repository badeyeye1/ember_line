defmodule EmberLine.Modeling.Project.SplitPrototype do
  @moduledoc """
  Command SplitPrototype (slice split-pages).

  The browser does the split before the command: it runs the loaded file in
  a hidden frame, visits every role and page, and reports how many pages and
  roles it found and whether its 4 minutes ran out. Fields are the model's,
  plus `split_at`: time arrives in the command.
  """

  @type t :: %__MODULE__{
          project_id: Ecto.UUID.t(),
          prototype_id: Ecto.UUID.t(),
          found_page_count: non_neg_integer(),
          role_count: non_neg_integer(),
          timed_out: boolean(),
          split_by: Ecto.UUID.t() | nil,
          split_at: DateTime.t()
        }

  defstruct [
    :project_id,
    :prototype_id,
    :split_by,
    :split_at,
    found_page_count: 0,
    role_count: 0,
    timed_out: false
  ]
end
