defmodule EmberLineWeb.PageController do
  use EmberLineWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
