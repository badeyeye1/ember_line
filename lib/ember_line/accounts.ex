defmodule EmberLine.Accounts do
  @moduledoc "Accounts domain: users and their auth tokens (AshAuthentication)."
  use Ash.Domain,
    otp_app: :ember_line

  resources do
    resource EmberLine.Accounts.NotificationPreference
    resource EmberLine.Accounts.SignInFailureCount
    resource EmberLine.Accounts.Token
    resource EmberLine.Accounts.User
    resource EmberLine.Accounts.Workspace
  end
end
