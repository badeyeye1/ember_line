defmodule EmberLine.Events.DomainEvent do
  @moduledoc """
  One outbox row: an event from the model (`type`, e.g. "NotificationPreferenceChanged")
  on a state-stored stream, with its fields under the model's names in `data`.

  `data` keys are a contract with automations: add keys freely, never rename
  or remove one.
  """
  use Ash.Resource,
    otp_app: :ember_line,
    domain: EmberLine.Events,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "domain_events"
    repo EmberLine.Repo

    custom_indexes do
      index [:stream, :stream_id]
      index [:processed_at]
    end
  end

  actions do
    defaults [:read]

    create :record do
      accept [:type, :stream, :stream_id, :data, :occurred_at]
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :type, :string, allow_nil?: false, public?: true
    attribute :stream, :string, allow_nil?: false, public?: true
    attribute :stream_id, :uuid, allow_nil?: false, public?: true
    attribute :data, :map, allow_nil?: false, public?: true
    attribute :occurred_at, :utc_datetime_usec, allow_nil?: false, public?: true
    attribute :processed_at, :utc_datetime_usec, public?: true
  end
end
