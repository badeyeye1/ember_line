defmodule EmberLine.Accounts.Validations.WorkspaceNameGiven do
  @moduledoc "save-workspace rule (\"Name is empty\"): a workspace needs a name."
  use Ash.Resource.Validation

  @message "The workspace needs a name."

  def message, do: @message

  @impl true
  def validate(changeset, _opts, _context) do
    case Ash.Changeset.get_attribute(changeset, :name) do
      name when is_binary(name) ->
        if String.trim(name) == "", do: error(), else: :ok

      _ ->
        error()
    end
  end

  defp error, do: {:error, field: :name, message: @message}
end
