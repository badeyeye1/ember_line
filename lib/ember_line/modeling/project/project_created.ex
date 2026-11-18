defmodule EmberLine.Modeling.Project.ProjectCreated do
  @moduledoc """
  Event ProjectCreated, on the Project stream. Permanent: never change or
  remove a field; follow docs/skills/change-event-safely-skill.md.

  Stored with Commanded's module-name type, so this module must not be
  renamed or moved.
  """

  @derive Jason.Encoder
  defstruct [
    :project_id,
    :name,
    :description,
    :source_type,
    :folder_path,
    :repo_url,
    :branch,
    :stack,
    :persistence_mode,
    :created_at,
    :created_by,
    :workspace_id
  ]

  @type t :: %__MODULE__{}

  @source_types ~w(new local github)
  @persistence_modes ~w(event_sourced state_stored mixed)

  defimpl Commanded.Serialization.JsonDecoder do
    alias EmberLine.Modeling.Project.ProjectCreated

    # Stored JSON has strings; restore the enums and the timestamp.
    def decode(%ProjectCreated{} = event) do
      %{
        event
        | source_type: ProjectCreated.to_enum(event.source_type, :source_type),
          persistence_mode: ProjectCreated.to_enum(event.persistence_mode, :persistence_mode),
          created_at: ProjectCreated.to_datetime(event.created_at)
      }
    end
  end

  @doc false
  def to_enum(nil, _field), do: nil
  def to_enum(value, _field) when is_atom(value), do: value
  def to_enum(value, :source_type) when value in @source_types, do: String.to_existing_atom(value)

  def to_enum(value, :persistence_mode) when value in @persistence_modes,
    do: String.to_existing_atom(value)

  @doc false
  def to_datetime(%DateTime{} = at), do: at

  def to_datetime(at) when is_binary(at) do
    {:ok, datetime, 0} = DateTime.from_iso8601(at)
    datetime
  end
end
