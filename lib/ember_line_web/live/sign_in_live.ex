defmodule EmberLineWeb.SignInLive do
  @moduledoc """
  Screen signin (docs/design/screens/signin.*). The form posts to
  AshAuthentication's password sign-in endpoint, which signs the member in,
  or comes back here with "Incorrect email or password".
  """
  use EmberLineWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Sign in",
       form: to_form(%{}, as: :user),
       trigger_action: false
     )}
  end

  @impl true
  def handle_event("sign_in", %{"user" => params}, socket) do
    {:noreply, assign(socket, form: to_form(params, as: :user), trigger_action: true)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.auth flash={@flash}>
      <h1>Sign in</h1>
      <p class="sub">Welcome back. Sign in to your workspace.</p>

      <.form
        for={@form}
        id="sign-in-form"
        action={~p"/auth/user/password/sign_in"}
        method="post"
        phx-submit="sign_in"
        phx-trigger-action={@trigger_action}
      >
        <.field field={@form[:email]} type="email" label="Work email" autocomplete="email" required />
        <.field
          field={@form[:password]}
          type="password"
          label="Password"
          autocomplete="current-password"
          required
        />
        <%!-- "Keep me signed in" arrives with the signin slice (SignedIn.keepSignedIn). --%>
        <div class="ui-inrow justify-end!">
          <.link navigate={~p"/reset"}>Forgot password?</.link>
        </div>
        <.button variant="primary" wide type="submit" phx-disable-with="Signing in…">Sign in</.button>
      </.form>

      <p class="ui-auth-foot">New here? <.link navigate={~p"/register"}>Create an account</.link></p>
    </Layouts.auth>
    """
  end
end
