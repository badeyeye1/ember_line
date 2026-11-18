defmodule EmberLine.Accounts.Validations.WorkEmail do
  @moduledoc "register rule: the email must look like name@company.com."
  use Ash.Resource.Validation

  @format ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/

  @impl true
  def validate(changeset, _opts, _context) do
    email = changeset |> Ash.Changeset.get_argument(:email) |> to_string()

    if Regex.match?(@format, email),
      do: :ok,
      else: {:error, field: :email, message: "Enter a work email, like name@company.com."}
  end
end
