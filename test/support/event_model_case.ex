defmodule EmberLine.EventModelCase do
  @moduledoc """
  Given/When/Then for slices: aggregate decisions without an event store,
  and commands dispatched through the Commanded app for read models.
  """
  use ExUnit.CaseTemplate
  import ExUnit.Assertions

  using do
    quote do
      import EmberLine.EventModelCase
    end
  end

  @doc "Given events, when a command: assert the events or the error the aggregate decides."
  def assert_decides(aggregate, given, command, expected) do
    state = Enum.reduce(given, struct(aggregate), &aggregate.apply(&2, &1))

    case {aggregate.execute(state, command), expected} do
      {{:error, reason}, {:error, want}} -> assert reason == want
      {result, {:error, want}} -> flunk("expected error #{inspect(want)}, got #{inspect(result)}")
      {result, events} -> assert List.wrap(result) == List.wrap(events)
    end
  end

  @doc "Dispatch a command and wait for strongly consistent read models."
  def dispatch!(command) do
    assert :ok = EmberLine.CommandedApp.dispatch(command, consistency: :strong)
  end
end
