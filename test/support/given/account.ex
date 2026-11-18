defmodule EmberLine.Given.Account do
  @moduledoc "Given-helpers for the Account stream: reach prior state through its actions."

  alias EmberLine.Accounts.NotificationPreference
  alias EmberLine.Accounts.User

  @doc """
  An account to act as, with a sign-in token. Seeded directly, not
  registered, so other slices' tests don't depend on the registration rules.
  """
  def account do
    user =
      Ash.Seed.seed!(User, %{email: "member-#{System.unique_integer([:positive])}@example.com"})

    {:ok, token, _claims} = AshAuthentication.Jwt.token_for_user(user)
    Ash.Resource.put_metadata(user, :token, token)
  end

  # Given NotificationPreferenceChanged(accountId, kind, channel, enabled)
  def notification_preference_changed(account, kind, channel, enabled) do
    NotificationPreference.change_notification_preference!(kind, channel, enabled, actor: account)
  end
end
