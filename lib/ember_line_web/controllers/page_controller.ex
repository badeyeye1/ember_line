defmodule EmberLineWeb.PageController do
  use EmberLineWeb, :controller

  @doc """
  `/` has no screen of its own: signed-in members go to their account's
  notifications (the only signed-in screen so far), everyone else to sign in.
  """
  def home(conn, _params) do
    if conn.assigns[:current_user] do
      redirect(conn, to: ~p"/account/notifications")
    else
      redirect(conn, to: ~p"/sign-in")
    end
  end
end
