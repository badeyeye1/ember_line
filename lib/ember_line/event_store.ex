defmodule EmberLine.EventStore do
  @moduledoc "Postgres event store for the event-sourced streams: Project and Slice."
  use EventStore, otp_app: :ember_line
end
