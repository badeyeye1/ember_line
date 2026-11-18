defmodule EmberLine.Accounts do
  use Ash.Domain,
    otp_app: :ember_line

  resources do
    resource EmberLine.Accounts.Token
    resource EmberLine.Accounts.User
  end
end
