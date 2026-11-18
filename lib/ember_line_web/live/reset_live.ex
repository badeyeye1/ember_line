defmodule EmberLineWeb.ResetLive do
  @moduledoc """
  Screen reset (docs/design/screens/reset.*): set a new password from the
  link in the reset email. The form posts to AshAuthentication's reset
  endpoint, which checks the token and the password rules and signs the
  member in.
  """
  use EmberLineWeb, :live_view

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Set a new password",
       form: to_form(%{"reset_token" => token}, as: :user),
       error: nil,
       trigger_action: false
     )}
  end

  @impl true
  def handle_event("reset", %{"user" => params}, socket) do
    form = to_form(params, as: :user)

    if params["password"] == params["password_confirmation"] do
      {:noreply, assign(socket, form: form, error: nil, trigger_action: true)}
    else
      {:noreply, assign(socket, form: form, error: "The passwords don't match.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.auth flash={@flash}>
      <h1>Set a new password</h1>
      <p class="sub">Choose a password you don't use anywhere else.</p>

      <.form
        for={@form}
        id="reset-form"
        action={~p"/auth/user/password/reset"}
        method="post"
        phx-submit="reset"
        phx-trigger-action={@trigger_action}
      >
        <input type="hidden" name={@form[:reset_token].name} value={@form[:reset_token].value} />
        <.field
          field={@form[:password]}
          type="password"
          label="New password"
          autocomplete="new-password"
          required
        />
        <.field
          field={@form[:password_confirmation]}
          type="password"
          label="Confirm new password"
          autocomplete="new-password"
          required
        />
        <.notice :if={@error} tone="err">{@error}</.notice>
        <.button variant="primary" wide type="submit" phx-disable-with="Saving…">
          Save password and sign in
        </.button>
      </.form>
    </Layouts.auth>
    """
  end
end
