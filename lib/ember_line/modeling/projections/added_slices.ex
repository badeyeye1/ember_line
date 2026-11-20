defmodule EmberLine.Modeling.Projections.AddedSlices do
  @moduledoc """
  Read model AddedSlices (slice create-derived-slices): every slice added
  to a project, by hand or by a derive, so a derive can tell which outline
  slices already exist. Written only by
  `EmberLine.Modeling.Projections.SlicesToCreateProjection`; read-only here.
  """
  use Ash.Resource,
    otp_app: :ember_line,
    domain: EmberLine.Modeling,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "added_slices"
    repo EmberLine.Repo

    custom_indexes do
      index [:project_id]
    end
  end

  actions do
    defaults [:read]
  end

  attributes do
    attribute :slice_id, :uuid, primary_key?: true, allow_nil?: false, public?: true
    attribute :project_id, :uuid, allow_nil?: false, public?: true
    attribute :name, :string, allow_nil?: false, public?: true
    attribute :screen_id, :string, public?: true
  end
end
