defmodule EmberLineWeb.VerifySessionController do
  @moduledoc """
  Puts the session that verify-email started (SignedIn) into the browser's
  session, then opens the new account's workspace.
  """
  use EmberLineWeb, :controller

  require Ash.Query

  alias AshAuthentication.Plug.Helpers
  alias EmberLine.Accounts.Workspace

  def create(conn, %{"token" => token}) do
    with {:ok, %{"sub" => subject}, resource} <- AshAuthentication.Jwt.verify(token, :ember_line),
         {:ok, user} <- AshAuthentication.subject_to_user(subject, resource) do
      user = Ash.Resource.put_metadata(user, :token, token)

      conn
      |> Helpers.store_in_session(user)
      |> put_flash(:info, "Your email is verified. Welcome to Emberline.")
      |> redirect(to: landing(user))
    else
      _ ->
        conn
        |> put_flash(:error, "That link has expired. Sign in to continue.")
        |> redirect(to: ~p"/sign-in")
    end
  end

  # The first workspace's welcome screen (setup-workspace), where the new
  # member names it and says what they do.
  defp landing(user) do
    case Workspace
         |> Ash.Query.filter(owner_account_id == ^user.id)
         |> Ash.Query.sort(created_at: :asc)
         |> Ash.Query.limit(1)
         |> Ash.read_one!(actor: user) do
      nil -> ~p"/"
      workspace -> ~p"/workspaces/#{workspace.id}/welcome"
    end
  end
end
