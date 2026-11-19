defmodule EmberLine.Accounts.ResendCodeTest do
  @moduledoc "Slice resend-code: one test per scenario in docs/model.json."
  use EmberLine.DataCase, async: false

  import EmberLine.Given.Account
  import EmberLine.ScenarioCase
  import Swoosh.TestAssertions

  alias EmberLine.Accounts.User

  @event "VerificationCodeResent"

  defp resend(account), do: User.resend_verification_code(account.id)
  defp reloaded(account), do: Ash.get!(User, account.id, authorize?: false)

  test "Resend after the wait has passed" do
    {account, old_code} = account_registered(email: "ada@company.com")
    code_sent_seconds_ago(account, 60)
    before = reloaded(account)

    assert {:ok, _} = resend(account)

    [event] = assert_events(@event, account.id, 1)

    assert %{"accountId" => id, "email" => "ada@company.com", "resentAt" => resent_at} =
             event.data

    assert id == account.id

    after_resend = reloaded(account)
    assert {:ok, at, 0} = DateTime.from_iso8601(resent_at)
    assert DateTime.compare(at, after_resend.verification_code_sent_at) == :eq
    assert after_resend.verification_code_hash != before.verification_code_hash

    assert_email_sent(fn email ->
      assert email.to == [{"", "ada@company.com"}]
      [new_code] = Regex.run(~r/\b(\d{6})\b/, email.text_body, capture: :all_but_first)
      # The new code works; old_code only if the two random codes happen to be equal.
      assert {:ok, %{status: :verified}} = User.verify_email(account.id, new_code, nil)
      _ = old_code
    end)
  end

  test "Resend too soon" do
    {account, _code} = account_registered()
    code_sent_seconds_ago(account, 10)

    assert {:error, error} = resend(account)
    assert error_message?(error, "You can resend in 20 s.")
    assert_events(@event, account.id, 0)
  end

  test "Account already verified" do
    {account, code} = account_registered()
    {:ok, _} = User.verify_email(account.id, code, nil)

    assert {:error, error} = resend(account)
    assert error_message?(error, "This email is already verified.")
    assert_events(@event, account.id, 0)
  end

  test "Double click on resend" do
    {account, _code} = account_registered()
    code_sent_seconds_ago(account, 60)

    assert {:ok, _} = resend(account)
    assert {:error, error} = resend(account)
    assert error_message?(error, "You can resend in 30 s.")
    assert_events(@event, account.id, 1)
  end

  # Not a model scenario: two resends at the same moment send one code (the
  # account row is locked while the wait is checked).
  test "two resends at once send one code" do
    {account, _code} = account_registered()
    code_sent_seconds_ago(account, 60)

    results =
      [fn -> resend(account) end, fn -> resend(account) end]
      |> Enum.map(&Task.async/1)
      |> Enum.map(&Task.await/1)

    assert [{:ok, _}] = Enum.filter(results, &match?({:ok, _}, &1))
    assert_events(@event, account.id, 1)
  end
end
