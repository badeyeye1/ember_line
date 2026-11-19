defmodule EmberLine.Accounts.SignInFailureCount do
  @moduledoc """
  The failed sign-ins for one email address (slice signin): state, not
  events. Keyed by the lower-cased address, whether or not an account uses
  it, so a lock never reveals which emails have accounts.

  `failed_at` holds the failures of the last 15 minutes; `locked_until` is set
  when the fifth one lands. Read and written only through
  `EmberLine.Accounts.SignInLock`.
  """
  use Ash.Resource,
    otp_app: :ember_line,
    domain: EmberLine.Accounts,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "sign_in_failure_counts"
    repo EmberLine.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :start do
      accept [:email, :failed_at, :locked_until]
    end

    update :set do
      accept [:failed_at, :locked_until]
    end
  end

  # Internal only: SignInLock calls it with authorize?: false.
  policies do
    policy always() do
      forbid_if always()
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :email, :string, allow_nil?: false
    attribute :failed_at, {:array, :utc_datetime_usec}, allow_nil?: false, default: []
    attribute :locked_until, :utc_datetime_usec
  end

  identities do
    identity :one_count_per_email, [:email]
  end
end
