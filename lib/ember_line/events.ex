defmodule EmberLine.Events do
  @moduledoc """
  The outbox for state-stored streams: each action records the model's events
  as `DomainEvent` rows in the same transaction as its state change.
  """
  use Ash.Domain, otp_app: :ember_line

  resources do
    resource EmberLine.Events.DomainEvent
  end
end
