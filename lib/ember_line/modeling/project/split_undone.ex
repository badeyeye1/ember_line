defmodule EmberLine.Modeling.Project.SplitUndone do
  @moduledoc """
  Event SplitUndone, on the Project stream (produced by slice undo-split).
  Permanent: never change or remove a field; follow
  docs/skills/change-event-safely-skill.md.

  Stored with Commanded's module-name type, so this module must not be
  renamed or moved.
  """

  @derive Jason.Encoder
  defstruct [:project_id, :prototype_id, :undone_by, :undone_at]

  @type t :: %__MODULE__{}

  defimpl Commanded.Serialization.JsonDecoder do
    alias EmberLine.Modeling.Project.PrototypeLoaded

    # Stored JSON has strings; restore the timestamp.
    def decode(event), do: %{event | undone_at: PrototypeLoaded.to_datetime(event.undone_at)}
  end
end
