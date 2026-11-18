defmodule EmberLine.Given.Account do
  @moduledoc "Given-helpers for the Account stream: reach prior state through its actions."

  alias EmberLine.Accounts.NotificationPreference
  alias EmberLine.Accounts.User

  @doc "A registered account to act as."
  def account do
    password = "correct horse battery staple"

    User
    |> Ash.Changeset.for_create(:register_with_password, %{
      email: "member-#{System.unique_integer([:positive])}@example.com",
      password: password,
      password_confirmation: password
    })
    |> Ash.create!(authorize?: false)
  end

  # Given NotificationPreferenceChanged(accountId, kind, channel, enabled)
  def notification_preference_changed(account, kind, channel, enabled) do
    NotificationPreference.change_notification_preference!(kind, channel, enabled, actor: account)
  end
end
