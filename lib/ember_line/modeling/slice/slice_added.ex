defmodule EmberLine.Modeling.Slice.SliceAdded do
  @moduledoc """
  Event SliceAdded, the first event on a Slice stream (slices add-slice and
  create-derived-slices). Permanent: never change or remove a field; follow
  docs/skills/change-event-safely-skill.md.

  Stored with Commanded's module-name type, so this module must not be
  renamed or moved.
  """

  @derive Jason.Encoder
  defstruct [
    :slice_id,
    :name,
    :pattern,
    :screen_id,
    :position,
    :project_id,
    :feature_id,
    :produces,
    :reads,
    :command_name,
    :read_model_name,
    :projection_name
  ]

  @type t :: %__MODULE__{}
end
