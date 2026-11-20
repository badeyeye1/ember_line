defmodule EmberLine.Modeling.Project.ModelDerived do
  @moduledoc """
  Event ModelDerived, on the Project stream (produced by slice derive-model).
  Permanent: never change or remove a field; follow
  docs/skills/change-event-safely-skill.md.

  Counts and ids only: the outline itself is in
  `EmberLine.Modeling.Derivation`, keyed by `derivation_id`. Stored with
  Commanded's module-name type, so this module must not be renamed or moved.
  """

  @derive Jason.Encoder
  defstruct [
    :derivation_id,
    :project_id,
    :prototype_id,
    :stack,
    :app_name,
    :screen_count,
    :slice_count,
    :outcome_count,
    :slice_ids,
    :not_in_new_outline,
    :derived_by,
    :derived_at
  ]

  @type t :: %__MODULE__{}

  defimpl Commanded.Serialization.JsonDecoder do
    alias EmberLine.Modeling.Project.PrototypeLoaded

    # Stored JSON has strings; restore the timestamp.
    def decode(event), do: %{event | derived_at: PrototypeLoaded.to_datetime(event.derived_at)}
  end
end
