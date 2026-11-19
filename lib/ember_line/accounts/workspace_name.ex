defmodule EmberLine.Accounts.WorkspaceName do
  @moduledoc """
  A new account's first workspace: "<first name>'s workspace", and its web
  address (slug). From verify-email's scenarios: "Ada Lovelace" gives
  "Ada's workspace" at `adas-workspace`.
  """

  require Ash.Query

  @doc "The first workspace's name."
  def for(%{full_name: name}) when is_binary(name) do
    case String.split(name, ~r/\s+/, trim: true) do
      [first | _] -> "#{first}'s workspace"
      [] -> "My workspace"
    end
  end

  def for(_account), do: "My workspace"

  @doc """
  The slug for a name: lower case, apostrophes dropped, anything else that
  isn't a letter or digit becomes a hyphen. No letters or digits at all gives
  "workspace" (the same fallback as setup-workspace).
  """
  def slug(name) do
    name
    |> String.downcase()
    |> String.replace(~r/['’]/u, "")
    |> String.replace(~r/[^\p{L}\p{N}]+/u, "-")
    |> String.trim("-")
    |> case do
      "" -> "workspace"
      slug -> slug
    end
  end

  @doc """
  The first free slug for `base` (`base`, `base-2`, `base-3`, ...), ignoring
  the workspace `own_id` itself. Call it inside the transaction that saves
  the slug: it takes an advisory lock on `base`, so two saves wanting the
  same slug can't both pick it. The unique index is the guarantee.
  """
  def free_slug!(base, own_id \\ nil) do
    EmberLine.Repo.query!("SELECT pg_advisory_xact_lock(hashtext($1))", [
      "workspace-slug:" <> base
    ])

    taken =
      EmberLine.Accounts.Workspace
      |> Ash.Query.filter(slug == ^base or like(slug, ^"#{base}-%"))
      |> then(fn query -> if own_id, do: Ash.Query.filter(query, id != ^own_id), else: query end)
      |> Ash.Query.select([:slug])
      |> Ash.read!(authorize?: false)
      |> MapSet.new(& &1.slug)

    Stream.iterate(2, &(&1 + 1))
    |> Stream.map(&"#{base}-#{&1}")
    |> then(&Stream.concat([base], &1))
    |> Enum.find(&(not MapSet.member?(taken, &1)))
  end
end
