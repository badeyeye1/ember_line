defmodule EmberLine.ScenarioCase do
  @moduledoc """
  Then-helpers for state-stored slices: the outbox rows an action wrote, and
  the validation message an action returned.
  """
  import ExUnit.Assertions
  require Ash.Query

  alias EmberLine.Events.DomainEvent

  @doc "The outbox events of `type` on `stream_id`, oldest first."
  def events(type, stream_id) do
    DomainEvent
    |> Ash.Query.filter(type == ^type and stream_id == ^stream_id)
    |> Ash.Query.sort(occurred_at: :asc)
    |> Ash.read!(authorize?: false)
  end

  @doc "Asserts exactly `count` events of `type` on `stream_id`, and returns them."
  def assert_events(type, stream_id, count) do
    found = events(type, stream_id)

    assert length(found) == count,
           "expected #{count} #{type} event(s), found #{length(found)}: #{inspect(Enum.map(found, & &1.data))}"

    found
  end

  @doc "True when an Ash error carries `message` (exact match)."
  def error_message?(%{errors: errors}, message),
    do: Enum.any?(errors, &error_message?(&1, message))

  def error_message?(%{message: message}, message), do: true
  def error_message?(_error, _message), do: false
end
