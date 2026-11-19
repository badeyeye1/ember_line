defmodule EmberLineWeb.WelcomeLiveTest do
  @moduledoc "Screen welcome: setup-workspace's Welcome form (docs/design/screens/welcome.*)."
  use EmberLineWeb.ConnCase, async: false

  import EmberLine.Given.Account
  import Phoenix.LiveViewTest

  alias AshAuthentication.Plug.Helpers, as: AuthHelpers
  alias EmberLine.Accounts.{User, Workspace}

  setup %{conn: conn} do
    {owner, _code} = account_registered(full_name: "Alex Rivera")

    workspace =
      workspace_created(owner, %{
        name: "Alex's workspace",
        slug: "w-#{System.unique_integer([:positive])}"
      })

    {:ok, token, _} = AshAuthentication.Jwt.token_for_user(owner)
    owner = Ash.Resource.put_metadata(owner, :token, token)
    conn = conn |> init_test_session(%{}) |> AuthHelpers.store_in_session(owner)
    %{conn: conn, owner: owner, workspace: workspace}
  end

  defp path(workspace), do: ~p"/workspaces/#{workspace.id}/welcome"

  test "greets the owner by first name, with the workspace's name filled in", %{
    conn: conn,
    workspace: workspace
  } do
    {:ok, view, html} = live(conn, path(workspace))

    assert html =~ "Welcome, Alex"

    assert has_element?(
             view,
             "#welcome_name[value=\"Alex&#39;s workspace\"], #welcome_name[value=\"Alex's workspace\"]"
           )

    assert has_element?(view, "input[name='welcome[title]'][value='Product'][checked]")
  end

  test "Name the workspace and pick a role", %{conn: conn, owner: owner, workspace: workspace} do
    {:ok, view, _html} = live(conn, path(workspace))

    assert {:error, {:live_redirect, %{to: to}}} =
             view
             |> form("#welcome-form", welcome: %{name: "Acme Studio", title: "Engineering"})
             |> render_submit()

    assert to == ~p"/workspaces/#{workspace.id}/projects"
    stored = Ash.get!(Workspace, workspace.id, authorize?: false)
    assert {stored.name, stored.slug} == {"Acme Studio", "acme-studio"}
    assert Ash.get!(User, owner.id, authorize?: false).title == "Engineering"
  end

  test "the browser's time zone goes on the profile", %{
    conn: conn,
    owner: owner,
    workspace: workspace
  } do
    conn = put_connect_params(conn, %{"time_zone" => "Europe/London"})
    {:ok, view, _html} = live(conn, path(workspace))

    view
    |> form("#welcome-form", welcome: %{name: "Acme Studio", title: "Product"})
    |> render_submit()

    assert Ash.get!(User, owner.id, authorize?: false).time_zone == "Europe/London"
  end

  test "Blank name is rejected", %{conn: conn, workspace: workspace} do
    {:ok, view, _html} = live(conn, path(workspace))

    html =
      view
      |> form("#welcome-form", welcome: %{name: "   ", title: "Product"})
      |> render_submit()

    assert html =~ "Give your workspace a name."
  end

  test "verifying an email lands on the welcome screen" do
    {account, code} = account_registered(full_name: "Grace Hopper")
    {:ok, %{token: token, workspace_id: workspace_id}} = User.verify_email(account.id, code, nil)

    conn = post(build_conn(), ~p"/verify/session", token: token)

    assert redirected_to(conn) == ~p"/workspaces/#{workspace_id}/welcome"
  end
end
