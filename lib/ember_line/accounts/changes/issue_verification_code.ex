defmodule EmberLine.Accounts.Changes.IssueVerificationCode do
  @moduledoc "After registering, email the account a 6-digit code to verify its address."
  use Ash.Resource.Change

  alias EmberLine.Accounts.VerificationCode

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, account ->
      :ok = VerificationCode.issue!(account)
      {:ok, Ash.get!(EmberLine.Accounts.User, account.id, authorize?: false)}
    end)
  end
end
