defmodule EmberLine.Modeling.Project.PrototypeLoaded do
  @moduledoc """
  Event PrototypeLoaded, on the Project stream. Permanent: never change or
  remove a field; follow docs/skills/change-event-safely-skill.md.

  Names only: the files themselves are in `EmberLine.Modeling.PrototypeFile`,
  never in an event. Stored with Commanded's module-name type, so this module
  must not be renamed or moved.
  """

  @derive Jason.Encoder
  defstruct [
    :prototype_id,
    :project_id,
    :source,
    :file_names,
    :file_count,
    :skipped_count,
    :ignored_file_names,
    :interactive,
    :loaded_by,
    :loaded_at
  ]

  @type t :: %__MODULE__{}

  defimpl Commanded.Serialization.JsonDecoder do
    alias EmberLine.Modeling.Project.PrototypeLoaded

    # Stored JSON has strings; restore the source and the timestamp.
    def decode(%PrototypeLoaded{} = event) do
      %{
        event
        | source: PrototypeLoaded.to_source(event.source),
          loaded_at: PrototypeLoaded.to_datetime(event.loaded_at)
      }
    end
  end

  @doc false
  def to_source(source) when source in [:files, :paste], do: source
  def to_source("files"), do: :files
  def to_source("paste"), do: :paste

  @doc false
  def to_datetime(%DateTime{} = at), do: at

  def to_datetime(at) when is_binary(at) do
    {:ok, datetime, 0} = DateTime.from_iso8601(at)
    datetime
  end
end
