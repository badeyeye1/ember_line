defmodule EmberLineWeb.SignupLive do
  @moduledoc """
  Screen signup: the Create account form (slice register).

  The form checks the RegisterAccount rules as you type and on submit. A
  valid submit runs the action, which records AccountRegistered and emails a
  6-digit code, then goes to the verify screen. Signing in comes from
  verify-email (SignedIn), not from registering.
  """
  use EmberLineWeb, :live_view

  alias EmberLine.Accounts.User

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Create your account",
       form: new_form()
     )}
  end

  @impl true
  def handle_event("validate", %{"user" => params}, socket) do
    {:noreply, assign(socket, form: AshPhoenix.Form.validate(socket.assigns.form, params))}
  end

  def handle_event("create", %{"user" => params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.form, params: params) do
      {:ok, account} ->
        {:noreply,
         push_navigate(socket, to: ~p"/verify/#{EmberLineWeb.VerifyLive.token_for(account)}")}

      {:error, form} ->
        {:noreply, assign(socket, form: form)}
    end
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
        phx-change="validate"
        phx-submit="create"
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
