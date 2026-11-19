defmodule EmberLine.Accounts.Changes.RecordWorkspaceDetailsSaved do
  @moduledoc """
  Records WorkspaceDetailsSaved (Workspace stream) in the outbox after
  :save_workspace_details writes, in the same transaction.

  `savedBy` is the actor, not a field of the record, and `savedAt` is the
  moment it was saved, so this doesn't use the generic RecordEvent change.
  """
  use Ash.Resource.Change

  alias EmberLine.Events

  @impl true
  def change(changeset, _opts, context) do
    actor_id = context.actor && context.actor.id

    Ash.Changeset.after_action(changeset, fn _changeset, workspace ->
      Events.record!("WorkspaceDetailsSaved", "Workspace", workspace.id, %{
        "workspaceId" => workspace.id,
        "name" => workspace.name,
        "slug" => workspace.slug,
        "defaultStack" => workspace.default_stack,
        "savedBy" => actor_id,
        "savedAt" => DateTime.utc_now()
      })

      {:ok, workspace}
    end)
  end
end
