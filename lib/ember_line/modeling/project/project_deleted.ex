defmodule EmberLine.Modeling.Project.ProjectDeleted do
  @moduledoc """
  Event ProjectDeleted, on the Project stream. Permanent: never change or
  remove a field; follow docs/skills/change-event-safely-skill.md.

  Stored with Commanded's module-name type, so this module must not be
  renamed or moved.
  """

  @derive Jason.Encoder
  defstruct [:project_id, :deleted_by, :deleted_at]

  @type t :: %__MODULE__{
          project_id: Ecto.UUID.t(),
          deleted_by: Ecto.UUID.t(),
          deleted_at: DateTime.t()
        }

  defimpl Commanded.Serialization.JsonDecoder do
    alias EmberLine.Modeling.Project.ProjectDeleted

    # Stored JSON has strings; restore the timestamp.
    def decode(%ProjectDeleted{} = event) do
      %{event | deleted_at: ProjectDeleted.to_datetime(event.deleted_at)}
    end
  end

  @doc false
  def to_datetime(%DateTime{} = at), do: at

  def to_datetime(at) when is_binary(at) do
    {:ok, datetime, 0} = DateTime.from_iso8601(at)
    datetime
  end
end
