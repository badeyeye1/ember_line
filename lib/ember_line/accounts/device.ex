defmodule EmberLine.Accounts.Device do
  @moduledoc """
  SignedIn.device: browser and operating system from a user agent, e.g.
  "Chrome on macOS". Coarse on purpose: no versions, nothing that identifies
  a person.
  """

  @browsers [
    {~r/Edg\//, "Edge"},
    {~r/OPR\/|Opera/, "Opera"},
    {~r/Firefox\//, "Firefox"},
    {~r/Chrome\/|CriOS\//, "Chrome"},
    {~r/Safari\//, "Safari"}
  ]

  @systems [
    {~r/iPhone|iPad|iPod/, "iOS"},
    {~r/Android/, "Android"},
    {~r/Mac OS X|Macintosh/, "macOS"},
    {~r/Windows/, "Windows"},
    {~r/CrOS/, "ChromeOS"},
    {~r/Linux/, "Linux"}
  ]

  def describe(nil), do: "Unknown device"
  def describe(""), do: "Unknown device"

  def describe(user_agent) do
    case {match(@browsers, user_agent), match(@systems, user_agent)} do
      {nil, nil} -> "Unknown device"
      {browser, nil} -> browser
      {nil, os} -> os
      {browser, os} -> "#{browser} on #{os}"
    end
  end

  defp match(patterns, user_agent) do
    Enum.find_value(patterns, fn {pattern, name} -> Regex.match?(pattern, user_agent) && name end)
  end
end
