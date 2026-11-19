defmodule EmberLine.Accounts.Changes.SlugFromName do
  @moduledoc """
  setup-workspace: the web address follows the workspace's name
  ("Acme & Co!" → `acme-co`, "!!!" → `workspace`). If another workspace has
  it, the next free one (`acme-studio-2`). Chosen inside the transaction.
  """
  use Ash.Resource.Change

  alias EmberLine.Accounts.WorkspaceName

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      case Ash.Changeset.get_attribute(changeset, :name) do
        name when is_binary(name) ->
          slug = name |> WorkspaceName.slug() |> WorkspaceName.free_slug!(changeset.data.id)
          Ash.Changeset.force_change_attribute(changeset, :slug, slug)

        _ ->
          changeset
      end
    end)
  end
end
