defmodule EmberLine.Accounts.ViewVerifyTest do
  @moduledoc "Slice view-verify, read model PendingVerification: one test per scenario."
  use EmberLine.DataCase, async: false

  import EmberLine.Given.Account

  alias EmberLine.Accounts.User

  defp query(account_id), do: User.pending_verification!(account_id, authorize?: false)

  defp close?(a, b), do: abs(DateTime.diff(a, b, :millisecond)) < 2_000

  test "Shows the email the code was sent to" do
    {account, _code} = account_registered(full_name: "Ada Lovelace", email: "ada@company.com")

    pending = query(account.id)

    assert pending.id == account.id
    assert to_string(pending.email) == "ada@company.com"
    assert close?(pending.code_sent_at, account.registered_at)
  end

  test "Resend updates the sent time" do
    {account, _code} = account_registered()
    code_sent_minutes_ago(account, 5)
    verification_code_resent(account)

    pending = query(account.id)

    assert close?(pending.code_sent_at, DateTime.utc_now())
    assert DateTime.diff(pending.resend_available_at, pending.code_sent_at, :second) == 30
  end

  test "No account is waiting to verify" do
    assert query(Ecto.UUID.generate()) == nil
  end

  test "Several resends keep only the latest time" do
    {account, _code} = account_registered()

    times =
      for _ <- 1..3 do
        verification_code_resent(account)
        Ash.get!(User, account.id, authorize?: false).verification_code_sent_at
      end

    assert query(account.id).code_sent_at == List.last(times)
  end

  # Not a model scenario: once verified, nothing is waiting.
  test "a verified account has nothing waiting" do
    {account, code} = account_registered()
    {:ok, _} = User.verify_email(account.id, code, nil)

    assert query(account.id) == nil
  end
end
