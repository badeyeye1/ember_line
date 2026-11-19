defmodule EmberLine.Accounts.TimeZone do
  @moduledoc """
  ProfileSaved.timeZone: an IANA time zone name the database knows
  (`pg_timezone_names`). A missing or unknown one becomes "UTC"
  (setup-workspace).
  """

  @doc "The time zone to store for what the browser reported."
  def normalize(name) when is_binary(name) do
    name = String.trim(name)

    if name != "" and known?(name), do: name, else: "UTC"
  end

  def normalize(_name), do: "UTC"

  defp known?(name) do
    %{rows: rows} =
      EmberLine.Repo.query!("SELECT 1 FROM pg_timezone_names WHERE name = $1 LIMIT 1", [name])

    rows != []
  end
end
