defmodule EmberLine.Modeling.Projections.SlicesToCreate do
  @moduledoc """
  Read model SlicesToCreate (slice create-derived-slices): the outline's
  slices the automation still has to add, with their details from the
  stored outline. Written only by
  `EmberLine.Modeling.Projections.SlicesToCreateProjection`; read-only here.
  """
  use Ash.Resource,
    otp_app: :ember_line,
    domain: EmberLine.Modeling,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "slices_to_create"
    repo EmberLine.Repo

    custom_indexes do
      index [:project_id, :position]
    end
  end

  code_interface do
    define :for_project, args: [:project_id]
  end

  actions do
    defaults [:read]

    read :for_project do
      argument :project_id, :uuid, allow_nil?: false
      filter expr(project_id == ^arg(:project_id))
      prepare build(sort: [position: :asc])
    end
  end

  attributes do
    attribute :slice_id, :uuid, primary_key?: true, allow_nil?: false, public?: true
    attribute :project_id, :uuid, allow_nil?: false, public?: true
    attribute :derivation_id, :uuid, allow_nil?: false, public?: true
    attribute :name, :string, allow_nil?: false, public?: true

    attribute :pattern, :string,
      allow_nil?: false,
      constraints: [match: ~r/\A(state_change|state_view|automation)\z/],
      public?: true

    attribute :screen_id, :string, public?: true
    attribute :position, :integer, allow_nil?: false, public?: true
    attribute :feature_id, :uuid, public?: true
    attribute :produces, {:array, :string}, allow_nil?: false, default: [], public?: true
    attribute :reads, {:array, :string}, allow_nil?: false, default: [], public?: true
    attribute :command_name, :string, allow_nil?: false, default: "", public?: true
    attribute :read_model_name, :string, allow_nil?: false, default: "", public?: true
  end
end
