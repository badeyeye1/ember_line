defmodule EmberLine.Accounts.Validations.CanChangeWorkspaceSettings do
  @moduledoc """
  save-workspace rule ("Actor is not an admin"): only owners and admins can
  change workspace settings.

  Member roles don't exist yet (they arrive with the Member slices), so for
  now only the workspace's owner may; every other account is refused. The
  check reads the workspace's own state (`owner_account_id`).
  """
  use Ash.Resource.Validation

  @message "only owners and admins can change workspace settings"

  def message, do: @message

  @impl true
  def validate(changeset, _opts, %{actor: %{id: actor_id}}) do
    if changeset.data.owner_account_id == actor_id, do: :ok, else: error()
  end

  def validate(_changeset, _opts, _context), do: error()

  defp error, do: {:error, field: :workspace_id, message: @message}
end
