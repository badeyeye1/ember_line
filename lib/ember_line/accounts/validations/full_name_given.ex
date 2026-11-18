defmodule EmberLine.Accounts.Validations.FullNameGiven do
  @moduledoc "register rule: a name is required."
  use Ash.Resource.Validation

  @impl true
  def validate(changeset, _opts, _context) do
    case Ash.Changeset.get_attribute(changeset, :full_name) do
      name when is_binary(name) and name != "" ->
        if String.trim(name) == "", do: error(), else: :ok

      _ ->
        error()
    end
  end

  defp error,
    do:
      {:error, field: :full_name, message: "Enter your name so teammates know who's commenting."}
end
