defmodule EmberLine.Accounts.Validations.WorkspaceStackListed do
  @moduledoc "save-workspace rule (\"Stack isn't one of the listed ones\"): defaultStack is one of `Workspace.stacks/0`."
  use Ash.Resource.Validation

  alias EmberLine.Accounts.Workspace

  @impl true
  def validate(changeset, _opts, _context) do
    if Ash.Changeset.get_attribute(changeset, :default_stack) in Workspace.stacks(),
      do: :ok,
      else: {:error, field: :default_stack, message: "Pick a stack from the list."}
  end
end
