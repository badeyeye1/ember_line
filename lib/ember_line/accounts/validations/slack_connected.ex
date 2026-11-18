defmodule EmberLine.Accounts.Validations.SlackConnected do
  @moduledoc """
  set-notif-pref rule: Slack can only be switched on when Slack is connected
  (SlackNotConnected).

  Connecting Slack is the connect-integration slice, which isn't built, so
  no workspace has Slack connected yet. When it is built, this check reads
  the connection instead.
  """
  use Ash.Resource.Validation

  @impl true
  def validate(changeset, _opts, _context) do
    if Ash.Changeset.get_attribute(changeset, :channel) == :slack and
         Ash.Changeset.get_attribute(changeset, :enabled) == true and not slack_connected?() do
      {:error, field: :channel, message: "SlackNotConnected"}
    else
      :ok
    end
  end

  defp slack_connected?, do: false
end
