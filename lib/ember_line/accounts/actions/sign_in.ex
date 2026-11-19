defmodule EmberLine.Accounts.Actions.SignIn do
  @moduledoc """
  Command SignIn (slice signin).

  Checks, in order: a valid email; a password; the account and its password
  (an unknown email gets the same answer as a wrong password, after the same
  bcrypt work, so sign-in doesn't reveal which emails have accounts); then a
  verified email (only after the password matched).

  On success: a session token, a remember-me token when keepSignedIn, and
  SignedIn in the outbox, in one transaction.
  """
  use Ash.Resource.Actions.Implementation

  require Ash.Query

  alias Ash.Error.Changes.InvalidArgument
  alias EmberLine.Accounts.{Device, User}
  alias EmberLine.Events
  alias EmberLine.Repo

  @wrong "That password doesn't match. Try again or reset it."
  @email_format ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/

  @impl true
  def run(input, _opts, _context) do
    email = input.arguments |> Map.get(:email) |> to_string() |> String.trim()
    password = Map.get(input.arguments, :password) || ""

    cond do
      not Regex.match?(@email_format, email) ->
        reject(:email, "Enter your work email, like name@company.com.")

      password == "" ->
        reject(:password, "Enter your password.")

      true ->
        check(email, password, input.arguments)
    end
  end

  defp check(email, password, args) do
    account = User |> Ash.Query.filter(email == ^email) |> Ash.read_one!(authorize?: false)

    cond do
      not password_matches?(account, password) ->
        reject(:password, @wrong)

      is_nil(account.confirmed_at) ->
        {:error,
         InvalidArgument.exception(
           field: :email,
           message: "Email not verified. Enter the 6-digit code to continue.",
           vars: [account_id: account.id]
         )}

      true ->
        signed_in(account, args[:keep_signed_in] == true, Device.describe(args[:device]))
    end
  end

  defp password_matches?(%User{hashed_password: hash}, password) when is_binary(hash),
    do: Bcrypt.verify_pass(password, hash)

  defp password_matches?(_account, _password), do: Bcrypt.no_user_verify()

  defp signed_in(account, keep_signed_in, device) do
    Repo.transaction(fn ->
      now = DateTime.utc_now()
      {:ok, token, claims} = AshAuthentication.Jwt.token_for_user(account)

      Events.record!("SignedIn", "Account", account.id, %{
        "accountId" => account.id,
        "signedInAt" => now,
        "method" => "password",
        "keepSignedIn" => keep_signed_in,
        "sessionId" => claims["jti"],
        "device" => device
      })

      %{account_id: account.id, token: token, remember_me: keep_signed_in && remember_me(account)}
    end)
    |> case do
      {:ok, %{remember_me: false} = result} -> {:ok, %{result | remember_me: nil}}
      other -> other
    end
  end

  # The remember-me add-on's token: long-lived, purpose "remember_me", put in
  # its cookie by EmberLineWeb.SessionController.
  defp remember_me(account) do
    {:ok, strategy} = AshAuthentication.Info.strategy(User, :remember_me)

    {:ok, token, _claims} =
      AshAuthentication.Jwt.token_for_user(account, %{"purpose" => "remember_me"},
        purpose: :remember_me,
        token_lifetime: strategy.token_lifetime
      )

    %{
      token: token,
      cookie_name: strategy.cookie_name,
      max_age: AshAuthentication.Utils.lifetime_to_seconds(strategy.token_lifetime)
    }
  end

  defp reject(field, message),
    do: {:error, InvalidArgument.exception(field: field, message: message)}
end
