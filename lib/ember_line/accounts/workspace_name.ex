defmodule EmberLine.Accounts.WorkspaceName do
  @moduledoc """
  A new account's first workspace: "<first name>'s workspace", and its web
  address (slug). From verify-email's scenarios: "Ada Lovelace" gives
  "Ada's workspace" at `adas-workspace`.
  """

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
end
