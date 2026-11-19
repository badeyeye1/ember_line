defmodule EmberLine.Accounts.Actions.ResendVerificationCode do
  @moduledoc """
  Command ResendVerificationCode (slice resend-code): a new code, at most one
  every 30 seconds. The new code replaces the old one (and resets the tries);
  VerificationCodeResent goes to the outbox in the same transaction. The
  account row is locked while the wait is checked, so a double click sends
  one code.
  """
  use Ash.Resource.Actions.Implementation

  require Ash.Query

  alias Ash.Error.Changes.InvalidArgument
  alias EmberLine.Accounts.{User, VerificationCode}
  alias EmberLine.Events
  alias EmberLine.Repo

  @impl true
  def run(input, _opts, _context) do
    {:ok, result} =
      Repo.transaction(fn ->
        now = DateTime.utc_now()

        case lock(input.arguments.account_id) do
          nil -> {:error, "Nothing to verify. Sign in first."}
          %{confirmed_at: %DateTime{}} -> {:error, "This email is already verified."}
          account -> resend(account, now, VerificationCode.resend_wait(account, now))
        end
      end)

    case result do
      {:ok, resent} ->
        {:ok, resent}

      {:error, message} ->
        {:error, InvalidArgument.exception(field: :account_id, message: message)}
    end
  end

  defp resend(_account, _now, wait) when wait > 0, do: {:error, "You can resend in #{wait} s."}

  defp resend(account, now, 0) do
    :ok = VerificationCode.issue!(account, now)

    Events.record!("VerificationCodeResent", "Account", account.id, %{
      "accountId" => account.id,
      "email" => to_string(account.email),
      "resentAt" => now
    })

    {:ok, %{account_id: account.id, resent_at: now}}
  end

  defp lock(account_id) do
    User
    |> Ash.Query.filter(id == ^account_id)
    |> Ash.Query.lock("FOR UPDATE")
    |> Ash.read_one!(authorize?: false)
  end
end
