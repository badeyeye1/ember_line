defmodule EmberLineWeb.BoardLiveTest do
  @moduledoc "Screen board, the intake panel: load-prototype's Choose files and paste HTML."
  use EmberLineWeb.ConnCase, async: false

  import EmberLine.Given.Account, only: [workspace_created: 1]
  import Phoenix.LiveViewTest

  alias Commanded.Aggregates.Aggregate
  alias EmberLine.CommandedApp
  alias EmberLine.Modeling.Project
  alias EmberLine.Modeling.Project.{CreateProject, DeleteProject}
  alias EmberLine.Modeling.{PrototypeFile, PrototypePage, Prototypes}

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

  # split-pages

  defp paste_interactive(view) do
    view
    |> form("#prototype-paste", paste: %{html: ~s(<a href="#b">B</a><section id="b"></section>)})
    |> render_change()
  end

  defp split_page(view, n, role) do
    hook = element(view, "#split-pages")

    render_hook(hook, "split_page", %{
      title: "Page #{n}",
      role: role,
      route: "#p#{n}",
      html: "<p>#{n}</p>"
    })
  end

  test "Split into pages shows only for an interactive prototype", ctx do
    {:ok, view, _html} = live(ctx.conn, path(ctx))
    refute has_element?(view, "#split-pages")

    view |> form("#prototype-paste", paste: %{html: "<h1>About</h1>"}) |> render_change()
    refute has_element?(view, "#split-pages")

    paste_interactive(view)

    assert has_element?(
             view,
             "#split-pages[phx-hook][data-src^='/prototype/']",
             "Split into pages"
           )
  end

  test "Split an interactive prototype: the pages are stored and the board says so", ctx do
    {:ok, view, _html} = live(ctx.conn, path(ctx))
    paste_interactive(view)

    for {n, role} <- [{1, "Host"}, {2, "Host"}, {3, "Member"}], do: split_page(view, n, role)

    render_hook(element(view, "#split-pages"), "split_done", %{
      found: 3,
      roles: 2,
      timed_out: false
    })

    assert has_element?(
             view,
             "#intake-note-0",
             "Split pasted-prototype.html into 3 pages across 2 roles. Each tab above is one page."
           )

    project = Aggregate.aggregate_state(CommandedApp, Project, "project-" <> ctx.project_id)

    assert ["Page 1", "Page 2", "Page 3"] =
             project.prototype_id |> PrototypePage.for_prototype!() |> Enum.map(& &1.title)
  end

  test "Already split: Split into pages hides until the split is undone", ctx do
    {:ok, view, _html} = live(ctx.conn, path(ctx))
    paste_interactive(view)
    split_page(view, 1, "")

    render_hook(element(view, "#split-pages"), "split_done", %{
      found: 1,
      roles: 0,
      timed_out: false
    })

    refute has_element?(view, "#split-pages")
  end

  # undo-split

  defp split_into(view, count) do
    for n <- 1..count, do: split_page(view, n, "")

    render_hook(element(view, "#split-pages"), "split_done", %{
      found: count,
      roles: 0,
      timed_out: false
    })
  end

  test "Undo after split: the pages go and Split into pages comes back", ctx do
    {:ok, view, _html} = live(ctx.conn, path(ctx))
    paste_interactive(view)
    refute has_element?(view, "#undo-split")

    split_into(view, 12)
    assert has_element?(view, "#intake-note-0 #undo-split", "Undo split")
    refute has_element?(view, "#split-pages")

    project = Aggregate.aggregate_state(CommandedApp, Project, "project-" <> ctx.project_id)
    assert length(PrototypePage.for_prototype!(project.prototype_id)) == 12

    view |> element("#undo-split") |> render_click()

    assert has_element?(
             view,
             "#intake-note-0",
             "Undid the split. The tabs show pasted-prototype.html again."
           )

    refute has_element?(view, "#undo-split")
    assert has_element?(view, "#split-pages")
    assert PrototypePage.for_prototype!(project.prototype_id) == []

    # Splitting again after an undo works.
    split_into(view, 2)
    assert has_element?(view, "#intake-note-0", "Split pasted-prototype.html into 2 pages.")
  end

  test "Already split elsewhere: Undo split is offered with the error", ctx do
    {:ok, view, _html} = live(ctx.conn, path(ctx))
    paste_interactive(view)
    project = Aggregate.aggregate_state(CommandedApp, Project, "project-" <> ctx.project_id)

    pages = [%{title: "Home", role: "", route: "#home", html: "<p></p>"}]

    {:ok, _split} =
      Prototypes.split(
        ctx.project_id,
        project.prototype_id,
        pages,
        1,
        0,
        false,
        ctx.user.id
      )

    split_into(view, 1)

    assert has_element?(
             view,
             "#intake-error",
             "This prototype is already split. Undo the split first."
           )

    assert has_element?(view, "#intake-error #undo-split")
    view |> element("#undo-split") |> render_click()
    assert has_element?(view, "#intake-note-0", "Undid the split.")
  end

  test "Nothing was split: undone elsewhere first", ctx do
    {:ok, view, _html} = live(ctx.conn, path(ctx))
    paste_interactive(view)
    split_into(view, 1)

    project = Aggregate.aggregate_state(CommandedApp, Project, "project-" <> ctx.project_id)

    {:ok, _undone} =
      Prototypes.undo_split(ctx.project_id, project.prototype_id, ctx.user.id)

    view |> element("#undo-split") |> render_click()
    assert has_element?(view, "#intake-error", "There's no split to undo.")
  end

  test "Prototype does not respond", ctx do
    {:ok, view, _html} = live(ctx.conn, path(ctx))
    paste_interactive(view)

    render_hook(element(view, "#split-pages"), "split_done", %{
      found: 0,
      roles: 0,
      timed_out: true
    })

    assert has_element?(
             view,
             "#intake-error",
             "The prototype didn't respond while it was being split. Reload it and try again."
           )
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

  # view-intake

  test "Nothing loaded yet: the frame says so", ctx do
    {:ok, view, _html} = live(ctx.conn, path(ctx))

    assert has_element?(view, ".ui-screen-frame #screen-label", "No prototype yet")

    assert has_element?(
             view,
             "#screen-view .ui-nomatch",
             "Drop the prototype above to see its screens here."
           )

    refute has_element?(view, "[role=tab]")
  end

  test "Shows loaded files as tabs: HTML static, screenshots as images", ctx do
    {:ok, view, _html} = live(ctx.conn, path(ctx))

    input =
      file_input(view, "#prototype-files", :prototype, [
        %{name: "board.html", content: "<p>board</p>", type: "text/html"},
        %{name: "home.png", content: "png", type: "image/png"}
      ])

    for name <- ["board.html", "home.png"], do: render_upload(input, name)

    assert has_element?(view, "[role=tab][aria-selected=true]", "board.html")
    assert has_element?(view, "[role=tab][aria-selected=false]", "home.png")
    assert has_element?(view, "#screen-label", "board.html · 1 of 2")
    assert has_element?(view, "#screen-view iframe[sandbox=''][src^='/prototype/']")

    view |> element("[role=tab]", "home.png") |> render_click()

    assert has_element?(view, "[role=tab][aria-selected=true]", "home.png")
    assert has_element?(view, "#screen-label", "home.png · 2 of 2")
    assert has_element?(view, "#screen-view img[alt='home.png'][src^='/prototype/']")
  end

  test "An interactive prototype runs live, with no tab bar for one file", ctx do
    {:ok, view, _html} = live(ctx.conn, path(ctx))
    paste_interactive(view)

    refute has_element?(view, "[role=tab]")
    assert has_element?(view, "#screen-label", "pasted-prototype.html")
    assert has_element?(view, "#screen-view iframe[sandbox='allow-scripts'][src^='/prototype/']")
  end

  test "Split replaces tabs with pages", ctx do
    {:ok, view, _html} = live(ctx.conn, path(ctx))
    paste_interactive(view)

    for {n, role} <- [{1, "Host"}, {2, "Member"}], do: split_page(view, n, role)

    render_hook(element(view, "#split-pages"), "split_done", %{
      found: 2,
      roles: 2,
      timed_out: false
    })

    assert has_element?(view, "[role=tab][aria-selected=true]", "Host · Page 1")
    assert has_element?(view, "[role=tab]", "Member · Page 2")
    assert has_element?(view, "#screen-view iframe[sandbox=''][src^='/prototype/']")
  end

  test "Notes come back after a reload", ctx do
    {:ok, view, _html} = live(ctx.conn, path(ctx))

    input =
      file_input(view, "#prototype-files", :prototype, [
        %{name: "a.html", content: "<p>a</p>", type: "text/html"},
        %{name: "notes.txt", content: "x", type: "text/plain"}
      ])

    for name <- ["a.html", "notes.txt"], do: render_upload(input, name)

    {:ok, view, _html} = live(ctx.conn, path(ctx))

    assert has_element?(
             view,
             "#intake-note-0",
             "Ignored notes.txt: only HTML, screenshots and .zip files are used."
           )

    assert has_element?(view, "#screen-label", "a.html")
  end

  test "A split shows again after a reload, with Undo split", ctx do
    {:ok, view, _html} = live(ctx.conn, path(ctx))
    paste_interactive(view)
    split_into(view, 3)

    {:ok, view, _html} = live(ctx.conn, path(ctx))

    assert has_element?(
             view,
             "#intake-note-0",
             "Split pasted-prototype.html into 3 pages. Each tab above is one page."
           )

    assert has_element?(view, "[role=tab]", "Page 3")
    refute has_element?(view, "#split-pages")

    view |> element("#undo-split") |> render_click()

    assert has_element?(
             view,
             "#intake-note-0",
             "Undid the split. The tabs show pasted-prototype.html again."
           )

    assert has_element?(view, "#screen-label", "pasted-prototype.html")
    assert has_element?(view, "#split-pages")
  end

  # derive-model

  defp stub_claude(text) do
    Req.Test.stub(EmberLine.Modeling.Derive.Claude, fn conn ->
      body =
        Enum.map_join(
          [
            %{
              "type" => "content_block_delta",
              "delta" => %{"type" => "text_delta", "text" => text}
            },
            %{"type" => "message_delta", "delta" => %{"stop_reason" => "end_turn"}}
          ],
          &"data: #{Jason.encode!(&1)}\n\n"
        )

      conn
      |> Plug.Conn.put_resp_content_type("text/event-stream")
      |> Plug.Conn.send_resp(200, body)
    end)
  end

  defp outline do
    Jason.encode!(%{
      "app" => %{"name" => "Studio Workshops"},
      "screens" => [%{"id" => "home", "name" => "Home"}],
      "outcomes" => [],
      "slices" => [
        %{
          "id" => "view-home",
          "name" => "View home",
          "pattern" => "state_view",
          "screen" => "home"
        },
        %{"id" => "rsvp", "name" => "RSVP", "pattern" => "state_change", "screen" => "home"}
      ]
    })
  end

  test "Derive model with nothing loaded says to upload first", ctx do
    {:ok, view, _html} = live(ctx.conn, path(ctx))

    view |> element("#derive-model", "Derive model") |> render_click()

    assert has_element?(
             view,
             "#derive-status.ui-note",
             "Upload the prototype first, then derive the model."
           )
  end

  test "Derive model: running with Stop, then the done sentence", ctx do
    {:ok, view, _html} = live(ctx.conn, path(ctx))
    view |> form("#prototype-paste", paste: %{html: "<h1>Home</h1>"}) |> render_change()
    stub_claude(outline())

    view |> element("#derive-model") |> render_click()

    assert has_element?(
             view,
             "#derive-status",
             "Claude is reading 1 file and mapping screens, slices and events. This takes a minute or two."
           )

    assert has_element?(view, "#stop-derive", "Stop")
    assert has_element?(view, "#derive-model[disabled]")

    Oban.drain_queue(queue: :derive)

    assert render(view) =~ "Mapped 1 screen into 2 slices."
    refute has_element?(view, "#stop-derive")
    refute has_element?(view, "#derive-model[disabled]")

    # The sentence comes back when the board is opened again.
    {:ok, view, _html} = live(ctx.conn, path(ctx))
    assert has_element?(view, "#derive-status", "Mapped 1 screen into 2 slices.")
  end

  test "Stop while running", ctx do
    {:ok, view, _html} = live(ctx.conn, path(ctx))
    view |> form("#prototype-paste", paste: %{html: "<h1>Home</h1>"}) |> render_change()

    view |> element("#derive-model") |> render_click()
    view |> element("#stop-derive") |> render_click()

    assert has_element?(view, "#derive-status", "Stopped.")
    refute has_element?(view, "#stop-derive")
  end

  test "Claude's answer can't be read: shown as an error", ctx do
    {:ok, view, _html} = live(ctx.conn, path(ctx))
    view |> form("#prototype-paste", paste: %{html: "<h1>Home</h1>"}) |> render_change()
    stub_claude("Sorry.")

    view |> element("#derive-model") |> render_click()
    Oban.drain_queue(queue: :derive)

    assert render(view) =~
             "Claude&#39;s answer couldn&#39;t be read. Press Derive model to try again."

    assert has_element?(view, "#derive-status.ui-note.err")
  end

  defp files_for(ctx) do
    project = Aggregate.aggregate_state(CommandedApp, Project, "project-" <> ctx.project_id)
    PrototypeFile.for_prototype!(project.prototype_id)
  end
end
