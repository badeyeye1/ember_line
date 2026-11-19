defmodule EmberLineWeb.SessionController do
  @moduledoc """
  Puts the session that SignIn started (SignedIn) into the browser, plus the
  remember-me cookie when the member chose "Keep me signed in", then opens
  their workspace.
  """
  use EmberLineWeb, :controller

  require Ash.Query

  alias AshAuthentication.Plug.Helpers
  alias AshAuthentication.Strategy.RememberMe.Plug.Helpers, as: RememberMeCookie
  alias EmberLine.Accounts.{User, Workspace}

  def create(conn, %{"token" => token} = params) do
    with {:ok, %{"sub" => subject}, resource} <- AshAuthentication.Jwt.verify(token, :ember_line),
         {:ok, user} <- AshAuthentication.subject_to_user(subject, resource) do
      return_to = get_session(conn, :return_to)

      conn
      |> delete_session(:return_to)
      |> Helpers.store_in_session(Ash.Resource.put_metadata(user, :token, token))
      |> maybe_remember(params["remember_me"])
      |> redirect(to: return_to || landing(user))
    else
      _ ->
        conn
        |> put_flash(:error, "That sign-in has expired. Try again.")
        |> redirect(to: ~p"/sign-in")
    end
  end

  # Only a valid remember-me token for this app is put in the cookie.
  defp maybe_remember(conn, token) when is_binary(token) and token != "" do
    with {:ok, %{"purpose" => "remember_me"}, _resource} <-
           AshAuthentication.Jwt.verify(token, :ember_line),
         {:ok, strategy} <- AshAuthentication.Info.strategy(User, :remember_me) do
      RememberMeCookie.put_remember_me_cookie(conn, to_string(strategy.cookie_name), %{
        token: token,
        max_age: AshAuthentication.Utils.lifetime_to_seconds(strategy.token_lifetime)
      })
    else
      _ -> conn
    end
  end

  defp maybe_remember(conn, _token), do: conn

  defp landing(user) do
    case Workspace
         |> Ash.Query.filter(owner_account_id == ^user.id)
         |> Ash.Query.sort(created_at: :asc)
         |> Ash.Query.limit(1)
         |> Ash.read_one!(actor: user) do
      nil -> ~p"/"
      workspace -> ~p"/workspaces/#{workspace.id}/projects"
    end
  end
end
