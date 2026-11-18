defmodule EmberLine.Accounts.NotificationPreference do
  @moduledoc """
  A member's choice for one kind of update on one channel (Account stream,
  state stored). Command ChangeNotificationPreference → event
  NotificationPreferenceChanged, recorded in the outbox.
  """
  use Ash.Resource,
    otp_app: :ember_line,
    domain: EmberLine.Accounts,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias EmberLine.Accounts.Validations

  postgres do
    table "notification_preferences"
    repo EmberLine.Repo

    references do
      reference :account, on_delete: :delete
    end
  end

  code_interface do
    define :change_notification_preference, args: [:kind, :channel, :enabled]
  end

  actions do
    defaults [:read]

    # Command ChangeNotificationPreference → event NotificationPreferenceChanged.
    # accountId is the signed-in actor. Setting the value it already has
    # changes nothing and records no event: the upsert only writes when
    # `enabled` differs, decided by the database.
    create :change_notification_preference do
      accept [:channel, :enabled]
      argument :kind, :string, allow_nil?: false

      upsert? true
      upsert_identity :one_choice_per_kind_and_channel
      upsert_fields [:enabled]
      upsert_condition expr(enabled != upsert_conflict(:enabled))
      return_skipped_upsert? true

      validate Validations.KnownNotificationKind
      validate Validations.SlackConnected

      change relate_actor(:account)

      change fn changeset, _context ->
        case Ash.Changeset.get_argument(changeset, :kind) do
          kind when is_binary(kind) ->
            if kind in Validations.KnownNotificationKind.kinds(),
              do:
                Ash.Changeset.force_change_attribute(
                  changeset,
                  :kind,
                  String.to_existing_atom(kind)
                ),
              else: changeset

          _ ->
            changeset
        end
      end

      change {EmberLine.Changes.RecordEvent,
              type: "NotificationPreferenceChanged",
              stream: "Account",
              stream_id: :account_id,
              fields: [
                {"accountId", :account_id},
                {"kind", :kind},
                {"channel", :channel},
                {"enabled", :enabled}
              ]}
    end
  end

  policies do
    policy action(:change_notification_preference) do
      authorize_if actor_present()
    end

    policy action_type(:read) do
      authorize_if expr(account_id == ^actor(:id))
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :kind, :atom,
      allow_nil?: false,
      public?: true,
      constraints: [one_of: [:mention, :review, :reply, :comment, :agent, :digest]]

    attribute :channel, :atom,
      allow_nil?: false,
      public?: true,
      constraints: [one_of: [:app, :email, :slack]]

    attribute :enabled, :boolean, allow_nil?: false, public?: true
  end

  relationships do
    belongs_to :account, EmberLine.Accounts.User, allow_nil?: false, public?: true
  end

  identities do
    identity :one_choice_per_kind_and_channel, [:account_id, :kind, :channel]
  end
end
