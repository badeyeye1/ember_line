defmodule EmberLineWeb.SignupLive do
  @moduledoc """
  Screen signup: the Create account form (slice register).

  The form checks the RegisterAccount rules as you type and on submit. A
  valid form is posted to AshAuthentication's register endpoint, which runs
  the same action, records AccountRegistered and signs the new member in.
  """
  use EmberLineWeb, :live_view

  alias EmberLine.Accounts.User

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Create your account",
       form: new_form(),
       trigger_action: false
     )}
  end

  @impl true
  def handle_event("validate", %{"user" => params}, socket) do
    {:noreply, assign(socket, form: AshPhoenix.Form.validate(socket.assigns.form, params))}
  end

  def handle_event("create", %{"user" => params}, socket) do
    form = AshPhoenix.Form.validate(socket.assigns.form, params)
    {:noreply, assign(socket, form: form, trigger_action: form.source.valid?)}
  end

  defp new_form do
    User
    |> AshPhoenix.Form.for_create(:register_account, as: "user", authorize?: false)
    |> to_form()
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.auth flash={@flash}>
      <h1>Create your account</h1>
      <p class="sub">Free for up to 3 people. No card needed.</p>

      <.form
        for={@form}
        id="register-form"
        action={~p"/auth/user/password/register"}
        method="post"
        phx-change="validate"
        phx-submit="create"
        phx-trigger-action={@trigger_action}
      >
        <.field field={@form[:full_name]} label="Full name" autocomplete="name" />
        <.field
          field={@form[:email]}
          type="email"
          label="Work email"
          autocomplete="email"
          placeholder="name@company.com"
        />
        <.field
          field={@form[:password]}
          type="password"
          label="Password"
          autocomplete="new-password"
          hint="At least 8 characters, with a letter and a number."
        />
        <.checkbox field={@form[:terms_accepted]}>
          I agree to the Terms of Service and Privacy Policy.
        </.checkbox>
        <.button variant="primary" wide type="submit" phx-disable-with="Creating account…">
          Create account
        </.button>
      </.form>

      <p class="ui-auth-foot">
        Already have an account? <.link navigate={~p"/sign-in"}>Sign in</.link>
      </p>
    </Layouts.auth>
    """
  end
end
