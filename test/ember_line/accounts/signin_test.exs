defmodule EmberLine.Accounts.SignInTest do
  @moduledoc "Slice signin: one test per scenario in docs/model.json."
  use EmberLine.DataCase, async: false

  import EmberLine.Given.Account
  import EmberLine.ScenarioCase

  require Ash.Query

  alias EmberLine.Accounts.User

  @device "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"
  @wrong "That email and password don't match. Try again or reset your password."
  @locked "Too many attempts. Try again in 15 minutes, or reset your password."

  defp sign_in(email, password, keep \\ true), do: User.sign_in(email, password, keep, @device)

  # Given AccountRegistered + EmailVerified
  defp verified_account(email) do
    {account, code} = account_registered(email: email, password: "demo1234a")
    {:ok, _} = User.verify_email(account.id, code, nil)
    account
  end

  test "Correct email and password" do
    account = verified_account("alex@acme.dev")

    assert {:ok, %{token: token, remember_me: remember_me}} =
             sign_in("alex@acme.dev", "demo1234a", true)

    [_from_verify, signed_in] = assert_events("SignedIn", account.id, 2)

    assert %{
             "accountId" => id,
             "method" => "password",
             "keepSignedIn" => true,
             "sessionId" => session_id,
             "device" => "Chrome on macOS",
             "signedInAt" => _
           } = signed_in.data

    assert id == account.id
    assert {:ok, %{"jti" => ^session_id}, _} = AshAuthentication.Jwt.verify(token, :ember_line)

    assert {:ok, %{"purpose" => "remember_me"}, _} =
             AshAuthentication.Jwt.verify(remember_me.token, :ember_line)
  end

  test "Wrong password" do
    account = verified_account("alex@acme.dev")

    assert {:error, error} = sign_in("alex@acme.dev", "wrong-password1")
    assert error_message?(error, @wrong)
    assert_events("SignedIn", account.id, 1)
  end

  test "Empty password" do
    verified_account("alex@acme.dev")

    for empty <- ["", nil] do
      assert {:error, error} = sign_in("alex@acme.dev", empty)
      assert error_message?(error, "Enter your password.")
    end
  end

  test "Email is not a valid address" do
    assert {:error, error} = sign_in("alex", "demo1234a", false)
    assert error_message?(error, "Enter your work email, like name@company.com.")
  end

  test "No account for the email" do
    assert {:error, error} = sign_in("nobody@company.com", "demo1234a")
    assert error_message?(error, @wrong)

    refute error_message?(
             error,
             "No account uses nobody@company.com. Check the address, or create an account."
           )
  end

  test "Account not yet verified is sent to verification instead of signed in" do
    {account, _code} = account_registered(email: "ada@company.com", password: "secret123")

    assert {:error, error} = sign_in("ada@company.com", "secret123")
    assert error_message?(error, "Email not verified. Enter the 6-digit code to continue.")
    assert unverified_account_id(error) == account.id
    assert_events("SignedIn", account.id, 0)
  end

  # Not a model scenario: without the right password, an unverified account
  # looks like any other wrong sign-in (nothing about verification leaks).
  test "an unverified account with the wrong password gets the usual answer" do
    account_registered(email: "ada@company.com", password: "secret123")

    assert {:error, error} = sign_in("ada@company.com", "not-it-123")
    assert error_message?(error, @wrong)
  end

  # Not a model scenario: no remember-me token unless asked for.
  test "keepSignedIn false gives no remember-me token" do
    account = verified_account("alex@acme.dev")

    assert {:ok, %{remember_me: nil}} = sign_in("alex@acme.dev", "demo1234a", false)
    [_, signed_in] = assert_events("SignedIn", account.id, 2)
    assert signed_in.data["keepSignedIn"] == false
  end

  test "email is matched ignoring case" do
    verified_account("alex@acme.dev")
    assert {:ok, _} = sign_in("Alex@Acme.dev", "demo1234a")
  end

  test "Too many wrong passwords" do
    verified_account("alex@acme.dev")
    sign_in_failed("alex@acme.dev", 5)
    sign_in_failures_minutes_ago("alex@acme.dev", 2)

    # The right password doesn't help while the address is locked.
    assert {:error, error} = sign_in("alex@acme.dev", "demo1234a")
    assert error_message?(error, @locked)
  end

  test "Too many tries on an email with no account" do
    sign_in_failed("nobody@company.com", 5)
    sign_in_failures_minutes_ago("nobody@company.com", 2)

    assert {:error, error} = sign_in("nobody@company.com", "demo1234a")
    assert error_message?(error, @locked)
  end

  test "The lock lifts 15 minutes after the fifth failure" do
    account = verified_account("alex@acme.dev")
    sign_in_failed("alex@acme.dev", 5)
    sign_in_failures_minutes_ago("alex@acme.dev", 15)

    assert {:ok, _} = sign_in("alex@acme.dev", "demo1234a")
    [_verify, signed_in] = assert_events("SignedIn", account.id, 2)
    assert signed_in.data["method"] == "password"
    assert failures("alex@acme.dev") == 0
  end

  test "A successful sign-in clears the count" do
    verified_account("alex@acme.dev")
    sign_in_failed("alex@acme.dev", 4)

    assert {:ok, _} = sign_in("alex@acme.dev", "demo1234a")
    assert failures("alex@acme.dev") == 0

    # One more wrong password is failure 1, not 5: the next attempt isn't locked.
    sign_in_failed("alex@acme.dev", 1)
    assert failures("alex@acme.dev") == 1
    assert {:ok, _} = sign_in("alex@acme.dev", "demo1234a")
  end

  test "Email case doesn't matter for the count" do
    verified_account("alex@acme.dev")
    sign_in_failed("alex@acme.dev", 4)

    assert {:error, error} = sign_in("Alex@Acme.dev", "wrong-password1")
    assert error_message?(error, @wrong)

    # That was failure 5 for alex@acme.dev: the next attempt is locked.
    assert {:error, error} = sign_in("alex@acme.dev", "demo1234a")
    assert error_message?(error, @locked)
  end

  # Not a model scenario: the lock comes before verification, too.
  test "a locked address is locked even before it's verified" do
    account_registered(email: "ada@company.com", password: "secret123")
    sign_in_failed("ada@company.com", 5)

    assert {:error, error} = sign_in("ada@company.com", "secret123")
    assert error_message?(error, @locked)
  end

  # Not a model scenario: failures older than 15 minutes drop out of the count.
  test "failures older than 15 minutes don't count" do
    verified_account("alex@acme.dev")
    sign_in_failed("alex@acme.dev", 4)
    sign_in_failures_minutes_ago("alex@acme.dev", 16)
    sign_in_failed("alex@acme.dev", 1)

    assert failures("alex@acme.dev") == 1
    assert {:ok, _} = sign_in("alex@acme.dev", "demo1234a")
  end

  defp failures(email) do
    case EmberLine.Accounts.SignInFailureCount
         |> Ash.Query.filter(email == ^email)
         |> Ash.read!(authorize?: false) do
      [] -> 0
      [count] -> length(count.failed_at)
    end
  end

  defp unverified_account_id(%{errors: errors}),
    do: Enum.find_value(errors, &unverified_account_id/1)

  defp unverified_account_id(%{vars: vars}) when is_list(vars), do: vars[:account_id]
  defp unverified_account_id(_), do: nil
end
