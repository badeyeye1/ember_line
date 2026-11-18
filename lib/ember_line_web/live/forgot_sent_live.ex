defmodule EmberLineWeb.ForgotSentLive do
  @moduledoc "Screen forgot-sent (docs/design/screens/forgot-sent.*): the reset link is on its way."
  use EmberLineWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Reset link sent")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.auth flash={@flash}>
      <h1>Check your email</h1>
      <p class="sub">If an account uses <b>that address</b>, a reset link is on its way.</p>
      <p class="ui-auth-foot">
        <.link navigate={~p"/reset"}>Try a different email</.link>
        · <.link navigate={~p"/sign-in"}>Back to sign in</.link>
      </p>
    </Layouts.auth>
    """
  end
end
