defmodule EmberLine.Secrets do
  @moduledoc "Supplies secrets to AshAuthentication, such as the token signing secret."
  use AshAuthentication.Secret

  def secret_for(
        [:authentication, :tokens, :signing_secret],
        EmberLine.Accounts.User,
        _opts,
        _context
      ) do
    Application.fetch_env(:ember_line, :token_signing_secret)
  end
end
