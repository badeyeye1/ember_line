defmodule EmberLine.Modeling.Project.DeriveModel do
  @moduledoc """
  Command DeriveModel (slice derive-model).

  Claude does the work before the command: the derive job sends the
  prototype, stores Claude's outline under `derivation_id`
  (`EmberLine.Modeling.Derivation`), then dispatches this with the counts
  and slice ids. Time and ids arrive in the command.
  """

  @type t :: %__MODULE__{
          derivation_id: Ecto.UUID.t(),
          project_id: Ecto.UUID.t(),
          prototype_id: Ecto.UUID.t(),
          stack: String.t(),
          app_name: String.t(),
          screen_count: non_neg_integer(),
          slice_count: non_neg_integer(),
          outcome_count: non_neg_integer(),
          slice_ids: [Ecto.UUID.t()],
          not_in_new_outline: [Ecto.UUID.t()],
          derived_by: Ecto.UUID.t() | nil,
          derived_at: DateTime.t()
        }

  defstruct [
    :derivation_id,
    :project_id,
    :prototype_id,
    :stack,
    :app_name,
    :derived_by,
    :derived_at,
    screen_count: 0,
    slice_count: 0,
    outcome_count: 0,
    slice_ids: [],
    not_in_new_outline: []
  ]
end
