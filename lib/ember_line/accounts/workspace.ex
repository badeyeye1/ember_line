defmodule EmberLine.Accounts.Workspace do
  @moduledoc """
  A workspace (Workspace stream, state stored). Created for a new account when
  it verifies its email (slice verify-email → WorkspaceCreated).
  """
  use Ash.Resource,
    otp_app: :ember_line,
    domain: EmberLine.Accounts,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "workspaces"
    repo EmberLine.Repo

    references do
      reference :owner_account, on_delete: :restrict
    end
  end

  actions do
    defaults [:read]

    # Internal: used by VerifyEmail inside its transaction.
    create :create_for_owner do
      accept [:name, :slug, :owner_account_id, :created_at]
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if expr(owner_account_id == ^actor(:id))
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, allow_nil?: false, public?: true
    attribute :slug, :string, allow_nil?: false, public?: true
    attribute :created_at, :utc_datetime_usec, allow_nil?: false, public?: true
  end

  relationships do
    belongs_to :owner_account, EmberLine.Accounts.User, allow_nil?: false, public?: true
  end

  identities do
    # One web address per workspace; a taken slug gets -2, -3, ...
    identity :unique_slug, [:slug]
  end
end
