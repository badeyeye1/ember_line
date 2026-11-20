defmodule EmberLine.Modeling.Slice do
  @moduledoc """
  The Slice aggregate: decides (`execute/2`) and records (`apply/2`) for the
  Slice stream. No database, clock or service calls; ids and positions
  arrive in the command.

  Rules that need other streams (the project exists, the board's 150 slice
  limit) are checked by `EmberLine.Modeling.Slices.add/1` before dispatch.
  """

  alias EmberLine.Modeling.Slice.{AddSlice, SliceAdded}

  defstruct [:slice_id, :project_id]

  @type t :: %__MODULE__{slice_id: Ecto.UUID.t() | nil, project_id: Ecto.UUID.t() | nil}

  # create-derived-slices

  # A slice id that already has a history records nothing and isn't an error,
  # so a restart part way through doesn't add a slice twice.
  def execute(%__MODULE__{slice_id: id}, %AddSlice{}) when not is_nil(id), do: []

  def execute(%__MODULE__{}, %AddSlice{} = c) do
    %SliceAdded{
      slice_id: c.slice_id,
      name: c.name,
      pattern: c.pattern,
      screen_id: c.screen_id,
      position: c.position,
      project_id: c.project_id,
      feature_id: c.feature_id,
      produces: c.produces,
      reads: c.reads,
      command_name: c.command_name,
      read_model_name: c.read_model_name,
      projection_name: c.projection_name
    }
  end

  def apply(%__MODULE__{} = slice, %SliceAdded{} = e),
    do: %{slice | slice_id: e.slice_id, project_id: e.project_id}
end
