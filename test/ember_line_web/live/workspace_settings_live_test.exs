defmodule EmberLineWeb.WorkspaceSettingsLiveTest do
  @moduledoc "Screen workspace-general: save-workspace's details card."
  use EmberLineWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import EmberLine.ScenarioCase

  alias AshAuthentication.Plug.Helpers, as: AuthHelpers
  alias EmberLine.Accounts.Workspace
  alias EmberLine.Given

  setup %{conn: conn} do
    user = Given.Account.account()
    workspace = Given.Account.workspace_created(user, %{name: "Acme", slug: "acme"})
    conn = conn |> init_test_session(%{}) |> AuthHelpers.store_in_session(user)
    %{conn: conn, user: user, workspace: workspace}
  end

  defp path(workspace), do: ~p"/workspaces/#{workspace.id}/settings"

  defp submit(view, params) do
    view |> form("#workspace-form", workspace: params) |> render_submit()
  end

  test "signed-out visitors are sent to sign in", %{workspace: workspace} do
    assert {:error, {:redirect, %{to: "/sign-in"}}} = live(build_conn(), path(workspace))
  end

  test "the form is prefilled from the workspace", %{conn: conn, workspace: workspace} do
    {:ok, view, html} = live(conn, path(workspace))

    assert html =~ "Settings for everyone in Acme."
    assert has_element?(view, "#workspace_name[value='Acme']")
    assert has_element?(view, "#workspace_slug[value='acme']")
    assert has_element?(view, ~s(.ui-pg-nav a[aria-current="page"]), "General")
  end

  test "Rename workspace", %{conn: conn, user: user, workspace: workspace} do
    {:ok, view, _html} = live(conn, path(workspace))

    html = submit(view, %{name: "Acme Labs", slug: "acme-labs", default_stack: "Other"})

    assert html =~ "Saved."
    assert has_element?(view, "#workspace_slug[value='acme-labs']")
    assert html =~ "Settings for everyone in Acme Labs."

    stored = Ash.get!(Workspace, workspace.id, actor: user)
    assert {stored.name, stored.slug, stored.default_stack} == {"Acme Labs", "acme-labs", "Other"}
    [event] = assert_events("WorkspaceDetailsSaved", workspace.id, 1)
    assert event.data["accountId"] == user.id
  end

  test "Name is empty", %{conn: conn, workspace: workspace} do
    {:ok, view, _html} = live(conn, path(workspace))

    html = submit(view, %{name: "", slug: "acme", default_stack: "Other"})

    assert html =~ "The workspace needs a name."
    refute html =~ "Saved."
  end

  test "Invalid URL", %{conn: conn, workspace: workspace} do
    {:ok, view, _html} = live(conn, path(workspace))

    html = submit(view, %{name: "Acme", slug: "Bad_URL!", default_stack: "Other"})

    assert html =~ "Use 2 to 39 lowercase letters, numbers or hyphens for the URL."
  end

  test "Actor is not an admin", %{workspace: workspace} do
    # Only the owner can open the page; anyone else is sent away with the rule.
    editor = Given.Account.account()

    conn =
      build_conn() |> init_test_session(%{}) |> AuthHelpers.store_in_session(editor)

    assert {:error, {:redirect, %{to: "/", flash: flash}}} = live(conn, path(workspace))
    assert flash["error"] == "only owners and admins can change workspace settings"
  end

  test "URL at the length boundaries", %{conn: conn, workspace: workspace} do
    {:ok, view, _html} = live(conn, path(workspace))

    assert submit(view, %{name: "Acme", slug: "ab", default_stack: "Other"}) =~ "Saved."
  end

  test "a URL another workspace has is taken", %{conn: conn, workspace: workspace} do
    Given.Account.workspace_created(Given.Account.account(), %{slug: "taken"})
    {:ok, view, _html} = live(conn, path(workspace))

    assert submit(view, %{name: "Acme", slug: "taken", default_stack: "Other"}) =~
             "That URL is taken."
  end
end
