defmodule EmberLine.Accounts.User do
  @moduledoc "A user account. Signs in with a password or a magic link."
  use Ash.Resource,
    otp_app: :ember_line,
    domain: EmberLine.Accounts,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshAuthentication]

  alias EmberLine.Accounts.Validations

  authentication do
    add_ons do
      log_out_everywhere do
        apply_on_password_change? true
      end

      confirmation :confirm_new_user do
        monitor_fields [:email]
        # Sign-up confirms by a 6-digit code (slice verify-email), not a link.
        confirm_on_create? false
        confirm_on_update? false
        require_interaction? true
        confirmed_at_field :confirmed_at
        auto_confirm_actions [:sign_in_with_magic_link, :reset_password_with_token]
        sender EmberLine.Accounts.User.Senders.SendNewUserConfirmationEmail
      end
    end

    tokens do
      enabled? true
      token_resource EmberLine.Accounts.Token
      signing_secret EmberLine.Secrets
      store_all_tokens? true
      require_token_presence_for_authentication? true
    end

    strategies do
      password :password do
        identity_field :email
        hash_provider AshAuthentication.BcryptProvider
        # Command RegisterAccount (slice register): the model's form has no
        # password confirmation field. Registering doesn't sign in: SignedIn
        # comes from VerifyEmail, so AshAuthentication's register endpoint is
        # off and the signup screen calls :register_account itself.
        registration_enabled? false
        confirmation_required? false

        resettable do
          sender EmberLine.Accounts.User.Senders.SendPasswordResetEmail
          # these configurations will be the default in a future release
          password_reset_action_name :reset_password_with_token
          request_password_reset_action_name :request_password_reset_token
        end
      end

      remember_me :remember_me

      magic_link do
        identity_field :email
        registration_enabled? true
        require_interaction? true

        sender EmberLine.Accounts.User.Senders.SendMagicLinkEmail
      end
    end
  end

  postgres do
    table "users"
    repo EmberLine.Repo
  end

  code_interface do
    define :verify_email, args: [:account_id, :code, :device]
    define :pending_verification, args: [:account_id], not_found_error?: false
    define :resend_verification_code, args: [:account_id]
  end

  actions do
    defaults [:read]

    read :get_by_subject do
      description "Get a user by the subject claim in a JWT"
      argument :subject, :string, allow_nil?: false
      get? true
      prepare AshAuthentication.Preparations.FilterBySubject
    end

    update :change_password do
      # Use this action to allow users to change their password by providing
      # their current password and a new password.

      require_atomic? false
      accept []
      argument :current_password, :string, sensitive?: true, allow_nil?: false

      argument :password, :string,
        sensitive?: true,
        allow_nil?: false,
        constraints: [min_length: 8]

      argument :password_confirmation, :string, sensitive?: true, allow_nil?: false

      validate confirm(:password, :password_confirmation)

      validate {AshAuthentication.Strategy.Password.PasswordValidation,
                strategy_name: :password, password_argument: :current_password}

      change {AshAuthentication.Strategy.Password.HashPasswordChange, strategy_name: :password}
    end

    read :sign_in_with_password do
      description "Attempt to sign in using a email and password."
      get? true

      argument :email, :ci_string do
        description "The email to use for retrieving the user."
        allow_nil? false
      end

      argument :password, :string do
        description "The password to check for the matching user."
        allow_nil? false
        sensitive? true
      end

      # validates the provided email and password and generates a token
      prepare AshAuthentication.Strategy.Password.SignInPreparation

      metadata :token, :string do
        description "A JWT that can be used to authenticate the user."
        allow_nil? false
      end
    end

    read :sign_in_with_token do
      # In the generated sign in components, we validate the
      # email and password directly in the LiveView
      # and generate a short-lived token that can be used to sign in over
      # a standard controller action, exchanging it for a standard token.
      # This action performs that exchange. If you do not use the generated
      # liveviews, you may remove this action, and set
      # `sign_in_tokens_enabled? false` in the password strategy.

      description "Attempt to sign in using a short-lived sign in token."
      get? true

      argument :token, :string do
        description "The short-lived sign in token."
        allow_nil? false
        sensitive? true
      end

      # validates the provided sign in token and generates a token
      prepare AshAuthentication.Strategy.Password.SignInWithTokenPreparation

      metadata :token, :string do
        description "A JWT that can be used to authenticate the user."
        allow_nil? false
      end
    end

    # Command RegisterAccount → event AccountRegistered (slice register).
    create :register_account do
      description "Register a new account with a name, email and password."
      accept [:full_name]

      argument :email, :ci_string do
        allow_nil? false
      end

      argument :password, :string do
        description "The proposed password for the user, in plain text."
        allow_nil? false
        sensitive? true
      end

      argument :terms_accepted, :boolean, default: false

      validate Validations.FullNameGiven
      validate Validations.WorkEmail
      validate Validations.EmailHasNoAccount
      validate Validations.StrongPassword
      validate Validations.TermsAccepted

      # Sets the email from the argument
      change set_attribute(:email, arg(:email))
      change set_attribute(:registered_at, &DateTime.utc_now/0)
      change EmberLine.Accounts.Changes.PickAvatarColor

      # Hashes the provided password
      change {AshAuthentication.Strategy.Password.HashPasswordChange, strategy_name: :password}

      # Emails a 6-digit code to verify the address (slice verify-email).
      change EmberLine.Accounts.Changes.IssueVerificationCode

      change {EmberLine.Changes.RecordEvent,
              type: "AccountRegistered",
              stream: "Account",
              stream_id: :id,
              fields: [
                {"accountId", :id},
                {"fullName", :full_name},
                {"email", :email},
                {"verified", &__MODULE__.verified?/1},
                {"registeredAt", :registered_at},
                {"avatarColor", :avatar_color}
              ]}

      # The unique index is the guarantee when two sign-ups race; say it in
      # the same words as the EmailHasNoAccount check.
      error_handler &Validations.EmailHasNoAccount.handle_identity_error/2
    end

    # Command VerifyEmail → EmailVerified, SignedIn and (for a first
    # workspace) WorkspaceCreated. See EmberLine.Accounts.Actions.VerifyEmail.
    action :verify_email, :map do
      argument :account_id, :uuid, allow_nil?: false
      argument :code, :string, allow_nil?: true
      argument :device, :string, allow_nil?: true, description: "The browser's user agent"
      run EmberLine.Accounts.Actions.VerifyEmail
    end

    # Command ResendVerificationCode → VerificationCodeResent (slice
    # resend-code). See EmberLine.Accounts.Actions.ResendVerificationCode.
    action :resend_verification_code, :map do
      argument :account_id, :uuid, allow_nil?: false
      run EmberLine.Accounts.Actions.ResendVerificationCode
    end

    # Read model PendingVerification (slice view-verify): an account still
    # waiting to verify its email, with where and when its code was sent.
    # No result for an unknown or already verified account. Only server code
    # that has proven the account id (the signed verify token) calls it.
    read :pending_verification do
      argument :account_id, :uuid, allow_nil?: false
      get? true
      filter expr(id == ^arg(:account_id) and is_nil(confirmed_at))
      prepare build(load: [:code_sent_at, :resend_available_at])
    end

    # The code's state, set when a code is issued or tried. Internal only.
    update :set_verification_code do
      accept [:verification_code_hash, :verification_code_sent_at, :verification_attempts]
    end

    action :request_password_reset_token do
      description "Send password reset instructions to a user if they exist."

      argument :email, :ci_string do
        allow_nil? false
      end

      # creates a reset token and invokes the relevant senders
      run {AshAuthentication.Strategy.Password.RequestPasswordReset, action: :get_by_email}
    end

    read :get_by_email do
      description "Looks up a user by their email"
      get_by :email
    end

    update :reset_password_with_token do
      argument :reset_token, :string do
        allow_nil? false
        sensitive? true
      end

      argument :password, :string do
        description "The proposed password for the user, in plain text."
        allow_nil? false
        constraints min_length: 8
        sensitive? true
      end

      # Optional: the password strategy has confirmation_required? false since
      # slice register, so the reset form no longer sends it.
      argument :password_confirmation, :string do
        description "The proposed password for the user (again), in plain text."
        allow_nil? true
        sensitive? true
      end

      # validates the provided reset token
      validate AshAuthentication.Strategy.Password.ResetTokenValidation

      # validates that the password matches the confirmation
      validate AshAuthentication.Strategy.Password.PasswordConfirmationValidation

      # Hashes the provided password
      change AshAuthentication.Strategy.Password.HashPasswordChange

      # Generates an authentication token for the user
      change AshAuthentication.GenerateTokenChange
    end

    create :sign_in_with_magic_link do
      description "Sign in or register a user with magic link."

      argument :token, :string do
        description "The token from the magic link that was sent to the user"
        allow_nil? false
      end

      argument :remember_me, :boolean do
        description "Whether to generate a remember me token"
        allow_nil? true
      end

      upsert? true
      upsert_identity :unique_email
      upsert_fields [:email]

      # Uses the information from the token to create or sign in the user
      change AshAuthentication.Strategy.MagicLink.SignInChange

      change {AshAuthentication.Strategy.RememberMe.MaybeGenerateTokenChange,
              strategy_name: :remember_me}

      metadata :token, :string do
        allow_nil? false
      end
    end

    action :request_magic_link do
      argument :email, :ci_string do
        allow_nil? false
      end

      run AshAuthentication.Strategy.MagicLink.Request
    end
  end

  policies do
    bypass AshAuthentication.Checks.AshAuthenticationInteraction do
      authorize_if always()
    end

    # Anyone may try a code: the code is the proof. Tries are counted and
    # limited in the action.
    policy action(:verify_email) do
      authorize_if always()
    end

    # Resends are limited to one every 30 seconds per account in the action.
    policy action(:resend_verification_code) do
      authorize_if always()
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :email, :ci_string do
      allow_nil? false
      public? true
    end

    attribute :hashed_password, :string do
      sensitive? true
    end

    attribute :confirmed_at, :utc_datetime_usec

    # Added by slice register. Nullable: accounts created before it have none.
    attribute :full_name, :string, public?: true
    attribute :avatar_color, :string, public?: true
    attribute :registered_at, :utc_datetime_usec, public?: true

    # Added by slice verify-email: the current code, hashed, and its tries.
    attribute :verification_code_hash, :string, sensitive?: true
    attribute :verification_code_sent_at, :utc_datetime_usec
    attribute :verification_attempts, :integer, allow_nil?: false, default: 0
  end

  calculations do
    # PendingVerification.codeSentAt and .resendAvailableAt (30 seconds later).
    calculate :code_sent_at, :utc_datetime_usec, expr(verification_code_sent_at)

    calculate :resend_available_at,
              :utc_datetime_usec,
              expr(datetime_add(verification_code_sent_at, 30, :second))
  end

  identities do
    identity :unique_email, [:email]
  end

  @doc "AccountRegistered.verified: the email has been confirmed."
  def verified?(user), do: not is_nil(user.confirmed_at)
end
