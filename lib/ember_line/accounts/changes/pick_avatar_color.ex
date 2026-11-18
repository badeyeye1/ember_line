defmodule EmberLine.Accounts.Changes.PickAvatarColor do
  @moduledoc """
  AccountRegistered.avatarColor: a colour for the account's initials,
  picked from a fixed palette by the account id, so it is stable.
  """
  use Ash.Resource.Change

  @palette ~w(#e07a5f #3d405b #81b29a #f2cc8f #6d597a #2a9d8f #e76f51 #457b9d)

  @impl true
  def change(changeset, _opts, _context) do
    id = Ash.Changeset.get_attribute(changeset, :id)

    Ash.Changeset.force_change_attribute(
      changeset,
      :avatar_color,
      Enum.at(@palette, :erlang.phash2(id, length(@palette)))
    )
  end
end
