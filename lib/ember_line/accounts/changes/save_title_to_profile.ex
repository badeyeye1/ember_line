defmodule EmberLine.Accounts.Changes.SaveTitleToProfile do
  @moduledoc """
  setup-workspace also saves the person's title to their profile and records
  ProfileSaved (Account stream), in the same transaction as the workspace.
  The other profile fields are the account's current ones; there is no time
  zone yet (save-profile adds it), so `timeZone` is null.
  """
  use Ash.Resource.Change

  alias EmberLine.Events

  @impl true
  def change(changeset, _opts, %{actor: actor}) do
    title = Ash.Changeset.get_argument(changeset, :title)

    Ash.Changeset.after_action(changeset, fn _changeset, workspace ->
      account =
        actor
        |> Ash.Changeset.for_update(:set_title, %{title: title})
        |> Ash.update!(authorize?: false)

      Events.record!("ProfileSaved", "Account", account.id, %{
        "accountId" => account.id,
        "fullName" => account.full_name,
        "title" => account.title,
        "timeZone" => nil,
        "avatarColor" => account.avatar_color
      })

      {:ok, workspace}
    end)
  end
end
