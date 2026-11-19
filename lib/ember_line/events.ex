defmodule EmberLine.Events do
  @moduledoc """
  The outbox for state-stored streams: each action records the model's events
  as `DomainEvent` rows in the same transaction as its state change.
  """
  use Ash.Domain, otp_app: :ember_line

  resources do
    resource EmberLine.Events.DomainEvent
  end

  @doc """
  Records one of the model's events in the outbox. Call it inside the
  transaction that makes the state change, so both commit or neither does.
  """
  def record!(type, stream, stream_id, data) do
    EmberLine.Events.DomainEvent
    |> Ash.Changeset.for_create(:record, %{
      type: type,
      stream: stream,
      stream_id: stream_id,
      data: data,
      occurred_at: DateTime.utc_now()
    })
    |> Ash.create!(authorize?: false)
  end
end
