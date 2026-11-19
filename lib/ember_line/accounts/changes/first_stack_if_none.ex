defmodule EmberLine.Accounts.Changes.FirstStackIfNone do
  @moduledoc """
  setup-workspace: a workspace starts on the first stack in the list
  (`Workspace.stacks/0`). A stack already chosen (in workspace settings) is
  kept.
  """
  use Ash.Resource.Change

  alias EmberLine.Accounts.Workspace

  @impl true
  def change(changeset, _opts, _context) do
    if is_nil(changeset.data.default_stack),
      do: Ash.Changeset.force_change_attribute(changeset, :default_stack, hd(Workspace.stacks())),
      else: changeset
  end
end
