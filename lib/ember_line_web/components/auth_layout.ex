defmodule EmberLineWeb.AuthLayout do
  @moduledoc """
  The auth shell as a LiveView layout, for the AshAuthentication.Phoenix pages
  Emberline doesn't replace (confirm email, magic link, sign out).

  Its own module, with no verified routes: the router refers to it at compile
  time (the routes' `layout:` option), so it mustn't depend on the router.
  """
  use Phoenix.Component

  import EmberLineWeb.UI, only: [auth_shell: 1]

  def auth_live(assigns) do
    ~H"""
    <.auth_shell>{@inner_content}</.auth_shell>
    """
  end
end
