defmodule EmberLineWeb.SignInLive do
  @moduledoc """
  Screen signin (docs/design/screens/signin.*): the Sign in button of slice
  signin. It runs SignIn; a new session (and the remember-me token, with
  "Keep me signed in") is handed to SessionController. An unverified account
  is sent to the verify screen.
  """
  use EmberLineWeb, :live_view

  alias EmberLine.Accounts.User
  alias EmberLineWeb.VerifyLive

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Sign in",
       form: to_form(%{"keep_signed_in" => "true"}, as: :user),
       user_agent: get_connect_info(socket, :user_agent),
       error: nil,
       session: nil
     )}
  end

  @impl true
  def handle_event("sign_in", %{"user" => params}, socket) do
    keep = params["keep_signed_in"] == "true"
    form = to_form(Map.delete(params, "password"), as: :user)

    case User.sign_in(params["email"], params["password"], keep, socket.assigns.user_agent) do
      {:ok, session} ->
        {:noreply, assign(socket, form: form, error: nil, session: session)}

      {:error, error} ->
        case unverified_account_id(error) do
          nil ->
            {:noreply, assign(socket, form: form, error: message(error))}

          account_id ->
            {:noreply,
             socket
             |> put_flash(:error, message(error))
             |> push_navigate(to: ~p"/verify/#{VerifyLive.token_for(%User{id: account_id})}")}
        end
    end
  end

  defp message(%{errors: [%{message: message} | _]}), do: message
  defp message(_error), do: "Something went wrong. Try again."

  defp unverified_account_id(%{errors: errors}),
    do: Enum.find_value(errors, &unverified_account_id/1)

  defp unverified_account_id(%{vars: vars}) when is_list(vars), do: vars[:account_id]
  defp unverified_account_id(_error), do: nil

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.auth flash={@flash}>
      <h1>Sign in</h1>
      <p class="sub">Welcome back. Sign in to your workspace.</p>

      <.form for={@form} id="sign-in-form" phx-submit="sign_in">
        <.field field={@form[:email]} type="email" label="Work email" autocomplete="email" required />
        <.field
          field={@form[:password]}
          type="password"
          label="Password"
          autocomplete="current-password"
          required
        />
        <div class="ui-inrow">
          <.checkbox field={@form[:keep_signed_in]}>Keep me signed in</.checkbox>
          <.link navigate={~p"/reset"}>Forgot password?</.link>
        </div>
        <.notice :if={@error} tone="err">{@error}</.notice>
        <.button variant="primary" wide type="submit" phx-disable-with="Signing in…">Sign in</.button>
      </.form>

      <%!-- SignIn started a session: post it so the browser keeps it. --%>
      <.form
        :if={@session}
        for={%{}}
        id="sign-in-session-form"
        action={~p"/session"}
        method="post"
        phx-trigger-action
      >
        <input type="hidden" name="token" value={@session.token} />
        <input
          :if={@session.remember_me}
          type="hidden"
          name="remember_me"
          value={@session.remember_me.token}
        />
      </.form>

      <p class="ui-auth-foot">New here? <.link navigate={~p"/register"}>Create an account</.link></p>
    </Layouts.auth>
    """
  end
end
