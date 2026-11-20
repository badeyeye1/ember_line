defmodule EmberLine.Modeling.Derivation do
  @moduledoc """
  The outline Claude derived (slice derive-model), state stored and keyed by
  derivationId: app, screens, streams, outcomes and slices, as Claude wrote
  them except that slice ids are uuids (an earlier slice keeps its id).
  ModelDerived counts it; create-derived-slices reads its slices.
  """
  use Ash.Resource,
    otp_app: :ember_line,
    domain: EmberLine.Modeling,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "derivations"
    repo EmberLine.Repo

    custom_indexes do
      index [:project_id, :derived_at]
    end
  end

  code_interface do
    define :store,
      args: [
        :derivation_id,
        :project_id,
        :app,
        :screens,
        :streams,
        :outcomes,
        :slices,
        :derived_at
      ]

    define :fetch, action: :read, get_by: [:derivation_id], not_found_error?: false
    define :latest_for_project, args: [:project_id], get?: true, not_found_error?: false
  end

  actions do
    defaults [:read, :destroy]

    create :store do
      accept [
        :derivation_id,
        :project_id,
        :app,
        :screens,
        :streams,
        :outcomes,
        :slices,
        :derived_at
      ]
    end

    read :latest_for_project do
      argument :project_id, :uuid, allow_nil?: false
      filter expr(project_id == ^arg(:project_id))
      prepare build(sort: [derived_at: :desc], limit: 1)
    end
  end

  attributes do
    attribute :derivation_id, :uuid, primary_key?: true, allow_nil?: false, public?: true
    attribute :project_id, :uuid, allow_nil?: false, public?: true
    attribute :app, :map, allow_nil?: false, default: %{}, public?: true
    attribute :screens, {:array, :map}, allow_nil?: false, default: [], public?: true
    attribute :streams, :map, allow_nil?: false, default: %{}, public?: true
    attribute :outcomes, {:array, :map}, allow_nil?: false, default: [], public?: true
    attribute :slices, {:array, :map}, allow_nil?: false, default: [], public?: true
    attribute :derived_at, :utc_datetime_usec, allow_nil?: false, public?: true
  end

  @doc "The outline stored under `derivation_id`, or nil."
  def get(derivation_id) do
    {:ok, derivation} = fetch(derivation_id, authorize?: false)
    derivation
  end

  @doc "The outline stored under `derivation_id`; raises if there is none."
  def get!(derivation_id),
    do: get(derivation_id) || raise(ArgumentError, "no derivation #{derivation_id}")
end
