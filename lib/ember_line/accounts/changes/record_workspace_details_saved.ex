defmodule EmberLine.Accounts.Changes.RecordWorkspaceDetailsSaved do
  @moduledoc """
  Records WorkspaceDetailsSaved (Workspace stream) in the outbox after
  :save_workspace_details writes, in the same transaction.

  `accountId` is the command's actorAccountId, which comes from the actor,
  not the record, so this doesn't use the generic RecordEvent change.
  `title` isn't part of SaveWorkspaceDetails: it is recorded as null until
  the model says where it comes from.
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
        "accountId" => actor_id,
        "title" => nil,
        "defaultStack" => workspace.default_stack
      })

      {:ok, workspace}
    end)
  end
end
