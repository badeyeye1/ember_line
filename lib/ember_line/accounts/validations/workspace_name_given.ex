defmodule EmberLine.Accounts.Validations.WorkspaceNameGiven do
  @moduledoc """
  A workspace needs a name. save-workspace says "The workspace needs a
  name."; setup-workspace says "Give your workspace a name." (`message:`).
  """
  use Ash.Resource.Validation

  @message "The workspace needs a name."

  def message, do: @message

  @impl true
  def validate(changeset, opts, _context) do
    message = opts[:message] || @message

    case Ash.Changeset.get_attribute(changeset, :name) do
      name when is_binary(name) ->
        if String.trim(name) == "", do: error(message), else: :ok

      _ ->
        error(message)
    end
  end

  defp error(message), do: {:error, field: :name, message: message}
end
