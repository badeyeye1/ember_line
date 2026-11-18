defmodule EmberLine.Accounts.Validations.TermsAccepted do
  @moduledoc "register rule: the terms must be accepted."
  use Ash.Resource.Validation

  @impl true
  def validate(changeset, _opts, _context) do
    if Ash.Changeset.get_argument(changeset, :terms_accepted) == true,
      do: :ok,
      else: {:error, field: :terms_accepted, message: "Agree to the terms to create an account."}
  end
end
