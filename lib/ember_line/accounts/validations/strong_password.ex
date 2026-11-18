defmodule EmberLine.Accounts.Validations.StrongPassword do
  @moduledoc "register rule: at least 8 characters, with a letter and a number."
  use Ash.Resource.Validation

  @impl true
  def validate(changeset, _opts, _context) do
    password = Ash.Changeset.get_argument(changeset, :password) || ""

    if String.length(password) >= 8 and password =~ ~r/\p{L}/u and password =~ ~r/\p{N}/u,
      do: :ok,
      else:
        {:error,
         field: :password, message: "Use at least 8 characters, with a letter and a number."}
  end
end
