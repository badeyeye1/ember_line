defmodule EmberLine.Accounts.Validations.KnownNotificationKind do
  @moduledoc "set-notif-pref rule: the kind must be one the model lists (UnknownNotificationKind)."
  use Ash.Resource.Validation

  @kinds ~w(mention review reply comment agent digest)

  def kinds, do: @kinds

  @impl true
  def validate(changeset, _opts, _context) do
    if Ash.Changeset.get_argument(changeset, :kind) in @kinds do
      :ok
    else
      {:error, field: :kind, message: "UnknownNotificationKind"}
    end
  end
end
