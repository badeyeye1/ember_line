defmodule EmberLine.Accounts.Validations.EmailHasNoAccount do
  @moduledoc """
  register rule: one account per email, ignoring case. Checked up front for
  the message; the `unique_email` index is the guarantee when two sign-ups
  race, and `handle_identity_error/2` gives that case the same words.
  """
  use Ash.Resource.Validation
  require Ash.Query

  alias Ash.Error.Changes.InvalidAttribute
  alias EmberLine.Accounts.User

  @impl true
  def validate(changeset, _opts, _context) do
    email = Ash.Changeset.get_argument(changeset, :email)

    if is_nil(email) or not taken?(email), do: :ok, else: error(email)
  end

  @doc "error_handler for :register_account: the unique index fired."
  def handle_identity_error(changeset, %{errors: errors} = error) when is_list(errors) do
    %{error | errors: Enum.map(errors, &handle_identity_error(changeset, &1))}
  end

  def handle_identity_error(changeset, %InvalidAttribute{field: :email} = error) do
    if error.message == "has already been taken" do
      InvalidAttribute.exception(
        field: :email,
        message: message(Ash.Changeset.get_argument(changeset, :email))
      )
    else
      error
    end
  end

  def handle_identity_error(_changeset, error), do: error

  defp taken?(email) do
    User
    |> Ash.Query.filter(email == ^email)
    |> Ash.exists?(authorize?: false)
  end

  defp error(email), do: {:error, field: :email, message: message(email)}

  defp message(email), do: "There's already an account for #{email}."
end
