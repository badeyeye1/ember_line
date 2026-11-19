defmodule EmberLineWeb.BoardLiveTest do
  @moduledoc "Screen board, the intake panel: load-prototype's Choose files and paste HTML."
  use EmberLineWeb.ConnCase, async: false

  import EmberLine.Given.Account, only: [workspace_created: 1]
  import Phoenix.LiveViewTest

  alias Commanded.Aggregates.Aggregate
  alias EmberLine.CommandedApp
  alias EmberLine.Modeling.Project
  alias EmberLine.Modeling.Project.{CreateProject, DeleteProject}
  alias EmberLine.Modeling.PrototypeFile

  setup ctx do
    ctx = register_and_sign_in(ctx)
    workspace = workspace_created(ctx.user)
    project_id = Ecto.UUID.generate()

    :ok =
      CommandedApp.dispatch(
        %CreateProject{
          project_id: project_id,
          name: "Studio Workshops",
          source_type: :new,
          created_by: ctx.user.id,
          workspace_id: workspace.id,
          created_at: DateTime.utc_now() |> DateTime.truncate(:second)
        },
        consistency: :strong
      )

    Map.merge(ctx, %{workspace: workspace, project_id: project_id})
  end

  defp path(ctx), do: ~p"/workspaces/#{ctx.workspace.id}/projects/#{ctx.project_id}"

  test "the intake panel has the reference's wording", ctx do
    {:ok, view, html} = live(ctx.conn, path(ctx))

    assert html =~ "Drop a whole prototype"
    assert html =~ "Choose files"
    assert has_element?(view, "textarea[placeholder='…or paste the HTML of a Claude prototype']")
    assert has_element?(view, ".ui-crumbs", "Studio Workshops")
  end

  test "Load several HTML files: they're stored under the prototype", ctx do
    {:ok, view, _html} = live(ctx.conn, path(ctx))

    input =
      file_input(view, "#prototype-files", :prototype, [
        %{name: "b.html", content: "<p>b</p>", type: "text/html"},
        %{name: "a.html", content: "<p>a</p>", type: "text/html"},
        %{name: "notes.txt", content: "x", type: "text/plain"},
        %{name: "logo.svg", content: "<svg/>", type: "image/svg+xml"}
      ])

    for name <- ["b.html", "a.html", "notes.txt", "logo.svg"], do: render_upload(input, name)

    assert render(view) =~
             "Ignored notes.txt and logo.svg: only HTML, screenshots and .zip files are used."

    refute has_element?(view, "#intake-error")
    assert [%{name: "a.html"}, %{name: "b.html"}] = files_for(ctx)
  end

  test "Paste the HTML of an interactive prototype", ctx do
    {:ok, view, _html} = live(ctx.conn, path(ctx))

    view
    |> form("#prototype-paste", paste: %{html: ~s(<a href="#b">B</a><section id="b"></section>)})
    |> render_change()

    refute has_element?(view, "#intake-error")
    assert [%{name: "pasted-prototype.html", type: "text/html"}] = files_for(ctx)
  end

  test "No usable screens", ctx do
    {:ok, view, _html} = live(ctx.conn, path(ctx))

    input =
      file_input(view, "#prototype-files", :prototype, [
        %{name: "notes.txt", content: "x", type: "text/plain"}
      ])

    render_upload(input, "notes.txt")

    assert has_element?(
             view,
             "#intake-error",
             "We couldn't find any screens in those files. Drop HTML files, screenshots or a .zip of the prototype."
           )
  end

  test "Files unreadable", ctx do
    {:ok, view, _html} = live(ctx.conn, path(ctx))

    input =
      file_input(view, "#prototype-files", :prototype, [
        %{name: "broken.zip", content: "nope", type: "application/zip"}
      ])

    render_upload(input, "broken.zip")

    assert has_element?(
             view,
             "#intake-error",
             "We couldn't read broken.zip. Check the file and try again."
           )
  end

  test "Deleted project", ctx do
    {:ok, view, _html} = live(ctx.conn, path(ctx))

    :ok =
      CommandedApp.dispatch(
        %DeleteProject{
          project_id: ctx.project_id,
          deleted_by: ctx.user.id,
          confirmed: true,
          deleted_at: DateTime.utc_now()
        },
        consistency: :strong
      )

    view |> form("#prototype-paste", paste: %{html: "<p>x</p>"}) |> render_change()
    assert has_element?(view, "#intake-error", "That project doesn't exist.")
  end

  test "No such project", ctx do
    assert {:error,
            {:live_redirect, %{to: to, flash: %{"error" => "That project doesn't exist."}}}} =
             live(ctx.conn, ~p"/workspaces/#{ctx.workspace.id}/projects/#{Ecto.UUID.generate()}")

    assert to == ~p"/workspaces/#{ctx.workspace.id}/projects"
  end

  test "someone else's workspace is refused", ctx do
    other = register_and_sign_in(%{conn: build_conn()})

    assert {:error, {:live_redirect, %{flash: %{"error" => "That project doesn't exist."}}}} =
             live(other.conn, path(ctx))
  end

  defp files_for(ctx) do
    project = Aggregate.aggregate_state(CommandedApp, Project, "project-" <> ctx.project_id)
    PrototypeFile.for_prototype!(project.prototype_id)
  end
end
