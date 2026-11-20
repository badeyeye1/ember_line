defmodule EmberLine.Modeling.Slice.AddSlice do
  @moduledoc """
  Command AddSlice (slices add-slice and create-derived-slices).

  Every value SliceAdded records arrives here. The create-derived-slices
  automation takes them from the stored outline; a slice added by hand
  leaves featureId, produces, reads and the names empty.
  """

  @type t :: %__MODULE__{
          slice_id: Ecto.UUID.t(),
          project_id: Ecto.UUID.t(),
          name: String.t(),
          pattern: String.t(),
          screen_id: String.t(),
          position: pos_integer(),
          after_slice_id: Ecto.UUID.t() | nil,
          feature_id: Ecto.UUID.t() | nil,
          produces: [String.t()],
          reads: [String.t()],
          command_name: String.t(),
          read_model_name: String.t(),
          projection_name: String.t()
        }

  defstruct [
    :slice_id,
    :project_id,
    :name,
    :pattern,
    :screen_id,
    :position,
    :after_slice_id,
    :feature_id,
    produces: [],
    reads: [],
    command_name: "",
    read_model_name: "",
    projection_name: ""
  ]
end
