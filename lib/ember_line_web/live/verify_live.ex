defmodule EmberLineWeb.VerifyLive do
  @moduledoc """
  Screen verify (docs/design/screens/verify.*): the Code form of slice
  verify-email. The URL carries a signed account id from sign-up. A valid
  code starts a session, which the screen hands to VerifySessionController
  to put in the browser's session.

  Showing the address the code went to belongs to view-verify, and "Resend
  the code" to resend-code; neither is built yet.
  """
  use EmberLineWeb, :live_view

  alias EmberLine.Accounts.User

  @salt "pending verification"
  @max_age 24 * 60 * 60

  @doc "The token in the verify URL for a just-registered account."
  def token_for(%User{id: id}), do: Phoenix.Token.sign(EmberLineWeb.Endpoint, @salt, id)

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    account_id =
      case Phoenix.Token.verify(EmberLineWeb.Endpoint, @salt, token, max_age: @max_age) do
        {:ok, id} -> id
        {:error, _} -> nil
      end

    {:ok,
     assign(socket,
       page_title: "Check your email",
       account_id: account_id,
       user_agent: get_connect_info(socket, :user_agent),
       error: nil,
       session_token: nil
     )}
  end

  @impl true
  def handle_event("verify", params, socket) do
    code =
      params
      |> Map.get("code", %{})
      |> Enum.sort_by(fn {i, _} -> String.to_integer(i) end)
      |> Enum.map_join(fn {_, digit} -> digit end)

    case User.verify_email(socket.assigns.account_id, code, socket.assigns.user_agent) do
      {:ok, %{status: :verified, token: token}} ->
        {:noreply, assign(socket, error: nil, session_token: token)}

      {:ok, %{status: :already_verified}} ->
        {:noreply,
         socket
         |> put_flash(:info, "Your email is already verified. Sign in to continue.")
         |> push_navigate(to: ~p"/sign-in")}

      {:error, error} ->
        {:noreply, assign(socket, error: message(error))}
    end
  end

  defp message(%{errors: [%{message: message} | _]}), do: message
  defp message(_error), do: "Something went wrong. Try again."

  @impl true
  def render(%{account_id: nil} = assigns) do
    ~H"""
    <Layouts.auth flash={@flash}>
      <h1>Nothing to verify</h1>
      <p class="sub">Sign in first.</p>
      <.button variant="primary" wide navigate={~p"/sign-in"}>Go to sign in</.button>
    </Layouts.auth>
    """
  end

  def render(assigns) do
    ~H"""
    <Layouts.auth flash={@flash}>
      <h1>Check your email</h1>
      <p class="sub">We sent a 6-digit code to your email. Enter it to confirm your address.</p>

      <form id="verify-form" phx-submit="verify">
        <.code_input name="code" label="6-digit code" invalid={@error != nil} />
        <p :if={@error} class="ui-ferr" role="alert">{@error}</p>
        <.button variant="primary" wide type="submit" phx-disable-with="Checking…">Verify email</.button>
      </form>

      <%!-- A valid code started a session: post it so the browser keeps it. --%>
      <.form
        :if={@session_token}
        for={%{}}
        id="verify-session-form"
        action={~p"/verify/session"}
        method="post"
        phx-trigger-action
      >
        <input type="hidden" name="token" value={@session_token} />
      </.form>

      <p class="ui-auth-foot"><.link navigate={~p"/sign-in"}>Use a different email</.link></p>
    </Layouts.auth>
    """
  end
end
