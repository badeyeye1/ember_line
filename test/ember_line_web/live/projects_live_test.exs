defmodule EmberLineWeb.ProjectsLiveTest do
  @moduledoc "Screen projects: create-project's Create project button and view-projects' list."
  use EmberLineWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias EmberLine.Modeling.Projections.ProjectList

  setup ctx do
    Map.put(register_and_sign_in(ctx), :workspace, Ecto.UUID.generate())
  end

  defp path(ctx), do: ~p"/workspaces/#{ctx.workspace}/projects"

  defp submit(view, params) do
    view |> form("#new-project-form", project: params) |> render_submit()
  end

  test "signed-out visitors are sent to sign in", %{workspace: workspace} do
    assert {:error, {:redirect, %{to: "/sign-in"}}} =
             live(build_conn(), ~p"/workspaces/#{workspace}/projects")
  end

  test "No projects yet", ctx do
    {:ok, view, _html} = live(ctx.conn, path(ctx))

    assert has_element?(view, "#new-project-form")
    refute has_element?(view, "#projects")
  end

  test "Start fresh project", ctx do
    {:ok, view, _html} = live(ctx.conn, path(ctx))

    submit(view, %{
      name: "Edgemastery",
      source_type: "new",
      stack: "Elixir: Phoenix LiveView + Ash + AshCommanded",
      persistence_mode: "event_sourced"
    })

    assert has_element?(view, "#projects", "Edgemastery")

    assert [row] = ProjectList.for_workspace!(ctx.workspace)
    assert row.name == "Edgemastery"
    assert row.source_type == :new
    assert row.persistence_mode == :event_sourced
    assert row.created_by_id == ctx.user.id
  end

  test "GitHub project with branch", ctx do
    {:ok, view, _html} = live(ctx.conn, path(ctx))

    submit(view, %{
      name: "Billing API",
      source_type: "github",
      repo_url: "https://github.com/acme/billing",
      branch: "main"
    })

    assert has_element?(view, "#projects", "Billing API")
    assert [%{source_type: :github}] = ProjectList.for_workspace!(ctx.workspace)
  end

  test "Name is missing", ctx do
    {:ok, view, _html} = live(ctx.conn, path(ctx))

    submit(view, %{name: "", source_type: "new"})

    assert has_element?(view, "#new-project-form", "Give the project a name.")
    assert ProjectList.for_workspace!(ctx.workspace) == []
  end

  test "GitHub source without a repository URL", ctx do
    {:ok, view, _html} = live(ctx.conn, path(ctx))

    submit(view, %{name: "Billing API", source_type: "github", repo_url: ""})

    assert has_element?(view, "#new-project-form", "Add the GitHub repository URL.")
    assert ProjectList.for_workspace!(ctx.workspace) == []
  end
end
