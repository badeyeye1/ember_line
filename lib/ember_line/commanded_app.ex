defmodule EmberLine.CommandedApp do
  @moduledoc "Commanded application for the event-sourced streams. Configured in config/*.exs."
  use Commanded.Application, otp_app: :ember_line

  router EmberLine.Modeling.Router
end
