defmodule EmberLine.Mailer do
  @moduledoc "Sends email through Swoosh. The sender address is configured as `:mail_from`."
  use Swoosh.Mailer, otp_app: :ember_line

  @doc "The {name, address} that outgoing email is sent from."
  def from, do: Application.fetch_env!(:ember_line, :mail_from)
end
