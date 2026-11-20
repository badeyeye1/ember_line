defmodule EmberLine.Modeling.DerivationRun do
  @moduledoc """
  One press of Derive model (slice derive-model), state stored: whether it
  is running, stopped, failed or done, and the board's sentence for it.
  The board shows the project's latest run.
  """
  use Ash.Resource,
    otp_app: :ember_line,
    domain: EmberLine.Modeling,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "derivation_runs"
    repo EmberLine.Repo

    custom_indexes do
      index [:project_id, :started_at]
    end
  end

  code_interface do
    define :start, args: [:derivation_id, :project_id, :message, :started_by, :started_at]
    define :finish, args: [:status, :message]
    define :latest_for_project, args: [:project_id], get?: true, not_found_error?: false
  end

  actions do
    defaults [:read]

    create :start do
      accept [:derivation_id, :project_id, :message, :started_by, :started_at]
      change set_attribute(:status, :running)
    end

    # running -> stopped | failed | done
    update :finish do
      require_atomic? false

      argument :status, :atom,
        allow_nil?: false,
        constraints: [one_of: [:stopped, :failed, :done]]

      argument :message, :string, allow_nil?: false
      change set_attribute(:status, arg(:status))
      change set_attribute(:message, arg(:message))
    end

    read :latest_for_project do
      argument :project_id, :uuid, allow_nil?: false
      filter expr(project_id == ^arg(:project_id))
      prepare build(sort: [started_at: :desc], limit: 1)
    end
  end

  attributes do
    attribute :derivation_id, :uuid, primary_key?: true, allow_nil?: false, public?: true
    attribute :project_id, :uuid, allow_nil?: false, public?: true

    attribute :status, :atom,
      allow_nil?: false,
      constraints: [one_of: [:running, :stopped, :failed, :done]],
      public?: true

    attribute :message, :string, allow_nil?: false, public?: true
    attribute :started_by, :uuid, allow_nil?: false, public?: true
    attribute :started_at, :utc_datetime_usec, allow_nil?: false, public?: true
  end
end
