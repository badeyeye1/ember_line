defmodule EmberLine.Accounts.Workspace do
  @moduledoc """
  A workspace (Workspace stream, state stored). Created for a new account when
  it verifies its email (slice verify-email → WorkspaceCreated); its details
  are changed by save-workspace (SaveWorkspaceDetails → WorkspaceDetailsSaved).
  """
  use Ash.Resource,
    otp_app: :ember_line,
    domain: EmberLine.Accounts,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias EmberLine.Accounts.{Changes, Validations}

  postgres do
    table "workspaces"
    repo EmberLine.Repo

    references do
      reference :owner_account, on_delete: :restrict
    end
  end

  code_interface do
    define :set_up_workspace, args: [:name, :title, :time_zone]
    define :save_workspace_details
  end

  actions do
    defaults [:read]

    # Internal: used by VerifyEmail inside its transaction.
    create :create_for_owner do
      accept [:name, :slug, :owner_account_id, :created_at]
    end

    # Command SaveWorkspaceDetails → event WorkspaceDetailsSaved (slice
    # save-workspace). actorAccountId is the actor, never a parameter.
    update :save_workspace_details do
      require_atomic? false
      accept [:name, :slug, :default_stack]

      validate Validations.CanChangeWorkspaceSettings
      validate Validations.WorkspaceNameGiven
      validate Validations.WorkspaceSlugValid
      validate Validations.WorkspaceStackListed

      change Changes.RecordWorkspaceDetailsSaved

      # The unique index is the guarantee when two workspaces race for the
      # same URL; say it in the same words as the up-front check.
      error_handler &Validations.WorkspaceSlugValid.handle_identity_error/2
    end

    # Command SetUpWorkspace (slice setup-workspace, the welcome form) →
    # WorkspaceDetailsSaved and ProfileSaved. The web address follows the
    # name (a taken one gets -2, -3, ...); savedBy is the actor.
    update :set_up_workspace do
      require_atomic? false
      accept [:name]

      argument :title, :string do
        allow_nil? false
        constraints match: ~r/\A(Product|Engineering|Design|Something else)\z/
      end

      # From the browser; missing or unknown becomes UTC (SaveTitleToProfile).
      argument :time_zone, :string, allow_nil?: true

      validate Validations.CanChangeWorkspaceSettings
      validate {Validations.WorkspaceNameGiven, message: "Give your workspace a name."}

      change Changes.SlugFromName
      change Changes.FirstStackIfNone
      change Changes.RecordWorkspaceDetailsSaved
      change Changes.SaveTitleToProfile
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if expr(owner_account_id == ^actor(:id))
    end

    # Who may save is a rule with the scenario's words, in
    # CanChangeWorkspaceSettings; the policy only needs someone acting.
    policy action([:save_workspace_details, :set_up_workspace]) do
      authorize_if actor_present()
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, allow_nil?: false, public?: true
    attribute :slug, :string, allow_nil?: false, public?: true
    attribute :created_at, :utc_datetime_usec, allow_nil?: false, public?: true

    # The default stack for new projects (save-workspace).
    attribute :default_stack, :string, public?: true
  end

  relationships do
    belongs_to :owner_account, EmberLine.Accounts.User, allow_nil?: false, public?: true
  end

  identities do
    # One web address per workspace; a taken slug gets -2, -3, ...
    identity :unique_slug, [:slug]
  end

  @stacks [
    "Elixir: Phoenix LiveView + Ash + AshCommanded",
    "Elixir: Phoenix LiveView + Ash",
    "Elixir: Phoenix LiveView + Ash + Commanded",
    "Elixir: Phoenix LiveView + Ash + Commanded + Hologram",
    "Elixir: Phoenix LiveView + Ash + Commanded + Elm",
    "Elixir: Phoenix LiveView + Commanded",
    "Other"
  ]

  @doc "WorkspaceDetailsSaved.defaultStack: the stacks the model lists."
  def stacks, do: @stacks
end
