defmodule EmberLineWeb.ProjectsLiveTest do
  @moduledoc "Screen projects: create-project's Create project button, view-projects' list and delete-project's Delete button."
  use EmberLineWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias EmberLine.CommandedApp
  alias EmberLine.Modeling.Project.{CreateProject, DeleteProject}
  alias EmberLine.Modeling.Projections.ProjectList

  setup ctx do
    Map.put(register_and_sign_in(ctx), :workspace, Ecto.UUID.generate())
  end

  defp path(ctx), do: ~p"/workspaces/#{ctx.workspace}/projects"

  defp submit(view, params) do
    view |> form("#new-project-form", project: params) |> render_submit()
  end

  # The repository fields appear once "GitHub repository" is chosen.
  defp choose_github(view) do
    view |> form("#new-project-form", project: %{source_type: "github"}) |> render_change()
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
    choose_github(view)

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
    choose_github(view)

    submit(view, %{name: "Billing API", source_type: "github", repo_url: ""})

    assert has_element?(view, "#new-project-form", "Add the GitHub repository URL.")
    assert ProjectList.for_workspace!(ctx.workspace) == []
  end

  # delete-project

  defp project!(ctx, name) do
    project_id = Ecto.UUID.generate()

    :ok =
      CommandedApp.dispatch(
        %CreateProject{
          project_id: project_id,
          name: name,
          source_type: :new,
          created_by: ctx.user.id,
          workspace_id: ctx.workspace,
          created_at: ~U[2026-11-18 10:00:00Z]
        },
        consistency: :strong
      )

    project_id
  end

  defp click_delete(view, project_id) do
    view |> element("#project-#{project_id} button", "Delete") |> render_click()
  end

  test "First click only asks to confirm", ctx do
    project_id = project!(ctx, "Emberline")
    {:ok, view, _html} = live(ctx.conn, path(ctx))

    click_delete(view, project_id)

    assert has_element?(
             view,
             "#project-#{project_id} [role=alert]",
             "Click Delete again to delete Emberline. This can't be undone."
           )

    assert [%{name: "Emberline"}] = ProjectList.for_workspace!(ctx.workspace)
  end

  test "Confirmed delete removes the project", ctx do
    project_id = project!(ctx, "Emberline")
    spare_id = project!(ctx, "Spare")
    {:ok, view, _html} = live(ctx.conn, path(ctx))

    click_delete(view, spare_id)
    click_delete(view, spare_id)

    refute has_element?(view, "#project-#{spare_id}")
    assert has_element?(view, "#project-#{project_id}", "Emberline")
    assert Enum.map(ProjectList.for_workspace!(ctx.workspace), & &1.name) == ["Emberline"]
  end

  # Not a model scenario: a first click on one card doesn't arm another.
  test "the second click must be on the same card", ctx do
    first = project!(ctx, "Emberline")
    second = project!(ctx, "Spare")
    {:ok, view, _html} = live(ctx.conn, path(ctx))

    click_delete(view, first)
    click_delete(view, second)

    assert has_element?(
             view,
             "#project-#{second} [role=alert]",
             "Click Delete again to delete Spare. This can't be undone."
           )

    refute has_element?(view, "#project-#{first} [role=alert]")
    assert length(ProjectList.for_workspace!(ctx.workspace)) == 2
  end

  test "Project does not exist", ctx do
    project_id = project!(ctx, "Emberline")
    {:ok, view, _html} = live(ctx.conn, path(ctx))

    # Deleted elsewhere (another tab) after this page loaded.
    :ok =
      CommandedApp.dispatch(
        %DeleteProject{
          project_id: project_id,
          deleted_by: ctx.user.id,
          confirmed: true,
          deleted_at: ~U[2026-11-19 09:30:00Z]
        },
        consistency: :strong
      )

    click_delete(view, project_id)

    assert render(view) =~ "That project doesn&#39;t exist."
    refute has_element?(view, "#project-#{project_id}")
  end

  # Not a model scenario: the screen only deletes projects it lists, so a
  # crafted event can't reach another workspace's project.
  test "a project from another workspace can't be deleted from this list", ctx do
    other = project!(%{ctx | workspace: Ecto.UUID.generate()}, "Elsewhere")
    {:ok, view, _html} = live(ctx.conn, path(ctx))

    render_click(view, "delete", %{"id" => other})
    render_click(view, "delete", %{"id" => other})

    assert render(view) =~ "That project doesn&#39;t exist."
    assert [_] = ProjectList |> Ash.read!() |> Enum.filter(&(&1.project_id == other))
  end
end
