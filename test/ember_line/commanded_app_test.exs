defmodule EmberLine.CommandedAppTest do
  use ExUnit.Case, async: false

  test "the Commanded application is running" do
    assert Process.whereis(EmberLine.CommandedApp)
  end
end
