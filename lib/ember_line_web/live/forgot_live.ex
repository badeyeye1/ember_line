defmodule EmberLineWeb.ForgotLive do
  @moduledoc """
  Screen forgot (docs/design/screens/forgot.*): ask for a reset link. Runs
  the password strategy's reset request, then shows forgot-sent. The answer
  is the same whether or not an account uses the address.
  """
  use EmberLineWeb, :live_view

  alias AshAuthentication.{Info, Strategy}
  alias EmberLine.Accounts.User

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Reset your password", form: to_form(%{}, as: :user))}
  end

  @impl true
  def handle_event("request", %{"user" => %{"email" => email}}, socket) do
    {:ok, strategy} = Info.strategy(User, :password)
    _ = Strategy.action(strategy, :reset_request, %{"email" => String.trim(email)})
    {:noreply, push_navigate(socket, to: ~p"/reset/sent")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.auth flash={@flash}>
      <h1>Reset your password</h1>
      <p class="sub">Enter the email you sign in with. We'll send a link to set a new password.</p>

      <.form for={@form} id="forgot-form" phx-submit="request">
        <.field field={@form[:email]} type="email" label="Work email" autocomplete="email" required />
        <.button variant="primary" wide type="submit" phx-disable-with="Sending…">Send reset link</.button>
      </.form>

      <p class="ui-auth-foot"><.link navigate={~p"/sign-in"}>Back to sign in</.link></p>
    </Layouts.auth>
    """
  end
end
