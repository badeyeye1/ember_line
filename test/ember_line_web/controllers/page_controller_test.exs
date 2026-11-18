defmodule EmberLineWeb.PageControllerTest do
  use EmberLineWeb.ConnCase

  test "GET / sends signed-out visitors to sign in", %{conn: conn} do
    assert redirected_to(get(conn, ~p"/")) == ~p"/sign-in"
  end
end
