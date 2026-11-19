defmodule EmberLine.Modeling.Projections.ProjectList do
  @moduledoc """
  Read model ProjectList (slice view-projects). Written only by
  `EmberLine.Modeling.Projections.ProjectListProjection`; read-only here.
  The table is rebuilt from events, so it is never the only place a fact lives.
  """
  use Ash.Resource,
    otp_app: :ember_line,
    domain: EmberLine.Modeling,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "project_list"
    repo EmberLine.Repo

    custom_indexes do
      index [:workspace_id]
    end
  end

  code_interface do
    define :for_workspace, args: [:workspace_id]
  end

  actions do
    defaults [:read]

    read :for_workspace do
      argument :workspace_id, :uuid, allow_nil?: false
      filter expr(workspace_id == ^arg(:workspace_id))
      prepare build(sort: [created_at: :asc, name: :asc])
    end
  end

  attributes do
    attribute :project_id, :uuid, primary_key?: true, allow_nil?: false, public?: true
    attribute :name, :string, allow_nil?: false, public?: true
    attribute :description, :string, public?: true
    attribute :stack, :string, public?: true

    attribute :persistence_mode, :atom,
      constraints: [one_of: [:event_sourced, :state_stored, :mixed]],
      public?: true

    attribute :source_type, :atom, constraints: [one_of: [:new, :local, :github]], public?: true
    attribute :is_sample, :boolean, allow_nil?: false, default: false, public?: true
    attribute :created_at, :utc_datetime, allow_nil?: false, public?: true
    attribute :created_by, :uuid, public?: true
    attribute :workspace_id, :uuid, public?: true
  end
end
