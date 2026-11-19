defmodule EmberLine.Accounts.Changes.SaveTitleToProfile do
  @moduledoc """
  setup-workspace also saves the person's title to their profile and records
  ProfileSaved (Account stream), in the same transaction as the workspace.
  The time zone comes from the browser; a missing or unknown one is stored as
  UTC. The other profile fields are the account's current ones.
  """
  use Ash.Resource.Change

  alias EmberLine.Accounts.TimeZone
  alias EmberLine.Events

  @impl true
  def change(changeset, _opts, %{actor: actor}) do
    title = Ash.Changeset.get_argument(changeset, :title)
    time_zone = TimeZone.normalize(Ash.Changeset.get_argument(changeset, :time_zone))

    Ash.Changeset.after_action(changeset, fn _changeset, workspace ->
      account =
        actor
        |> Ash.Changeset.for_update(:save_welcome_profile, %{title: title, time_zone: time_zone})
        |> Ash.update!(authorize?: false)

      Events.record!("ProfileSaved", "Account", account.id, %{
        "accountId" => account.id,
        "fullName" => account.full_name,
        "title" => account.title,
        "timeZone" => account.time_zone,
        "avatarColor" => account.avatar_color
      })

      {:ok, workspace}
    end)
  end
end
