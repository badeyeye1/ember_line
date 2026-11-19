defmodule EmberLine.Modeling.Project.PrototypeSplitIntoPages do
  @moduledoc """
  Event PrototypeSplitIntoPages, on the Project stream. Permanent: never
  change or remove a field; follow docs/skills/change-event-safely-skill.md.

  Counts only: the pages themselves are in `EmberLine.Modeling.PrototypePage`,
  never in an event. Stored with Commanded's module-name type, so this module
  must not be renamed or moved.
  """

  @derive Jason.Encoder
  defstruct [
    :project_id,
    :prototype_id,
    :page_count,
    :role_count,
    :skipped_count,
    :timed_out,
    :split_by,
    :split_at
  ]

  @type t :: %__MODULE__{}

  defimpl Commanded.Serialization.JsonDecoder do
    alias EmberLine.Modeling.Project.PrototypeLoaded

    # Stored JSON has strings; restore the timestamp.
    def decode(event), do: %{event | split_at: PrototypeLoaded.to_datetime(event.split_at)}
  end
end
