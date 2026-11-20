defmodule EmberLine.Modeling.ViewIntakeTest do
  @moduledoc """
  Slice view-intake, read model PrototypeScreens: the loaded prototype's tabs,
  whether it was split, and the board's notes.
  """
  use EmberLine.DataCase, async: false
  use EmberLine.EventModelCase

  alias EmberLine.Modeling.Project.{CreateProject, LoadPrototype, SplitPrototype, UndoSplit}
  alias EmberLine.Modeling.Projections.PrototypeScreens
  alias EmberLine.Modeling.PrototypePage

  @at ~U[2026-11-20 10:00:00Z]

  setup do
    account = Ecto.UUID.generate()
    project_id = Ecto.UUID.generate()

    dispatch!(%CreateProject{
      project_id: project_id,
      name: "Studio Workshops",
      source_type: :new,
      created_by: account,
      workspace_id: Ecto.UUID.generate(),
      created_at: @at
    })

    %{account: account, project_id: project_id, prototype_id: Ecto.UUID.generate()}
  end

  defp loaded!(ctx, file_names, fields \\ []) do
    dispatch!(
      struct!(
        LoadPrototype,
        Map.merge(
          %{
            project_id: ctx.project_id,
            prototype_id: ctx.prototype_id,
            source: :files,
            file_names: file_names,
            unreadable_file_names: [],
            ignored_file_names: [],
            too_large_file_names: [],
            interactive: false,
            total_bytes: 1000,
            loaded_by: ctx.account,
            loaded_at: @at
          },
          Map.new(fields)
        )
      )
    )
  end

  defp split!(ctx, pages, fields \\ []) do
    dispatch!(
      struct!(
        SplitPrototype,
        Map.merge(
          %{
            project_id: ctx.project_id,
            prototype_id: ctx.prototype_id,
            found_page_count: length(pages),
            role_count: 0,
            timed_out: false,
            split_by: ctx.account,
            split_at: @at
          },
          Map.new(fields)
        )
      )
    )

    stored =
      for {role, title} <- pages, do: %{title: title, role: role, route: nil, html: "<p></p>"}

    :ok = PrototypePage.replace!(ctx.prototype_id, stored)
  end

  defp screens(ctx), do: PrototypeScreens.for_project!(ctx.project_id)

  defp tabs(screens), do: Enum.map(screens.tabs, &{&1.label, &1.kind})

  test "Shows loaded files as tabs", ctx do
    loaded!(ctx, ["board.html", "home.png", "settings.html"])

    screens = screens(ctx)
    assert screens.file_count == 3
    assert screens.is_split == false

    assert tabs(screens) == [
             {"board.html", :static_html},
             {"home.png", :image},
             {"settings.html", :static_html}
           ]
  end

  test "An interactive prototype runs live", ctx do
    loaded!(ctx, ["app.html"], interactive: true)

    screens = screens(ctx)
    assert screens.file_count == 1
    assert screens.is_split == false
    assert tabs(screens) == [{"app.html", :live_html}]
  end

  test "Split replaces tabs with pages", ctx do
    loaded!(ctx, ["app.html"], interactive: true)

    split!(ctx, [{"Host", "Home"}, {"Host", "Workshops"}, {"Member", "Workshops"}], role_count: 2)

    screens = screens(ctx)
    assert screens.is_split == true
    assert screens.page_count == 3

    assert tabs(screens) == [
             {"Host · Home", :page},
             {"Host · Workshops", :page},
             {"Member · Workshops", :page}
           ]

    assert screens.notes == [
             "Split app.html into 3 pages across 2 roles. Each tab above is one page."
           ]
  end

  test "Pages of a prototype with no role picker", ctx do
    loaded!(ctx, ["app.html"], interactive: true)
    split!(ctx, [{nil, "Home"}, {"", "Settings"}])

    screens = screens(ctx)
    assert tabs(screens) == [{"Home", :page}, {"Settings", :page}]
    assert screens.notes == ["Split app.html into 2 pages. Each tab above is one page."]
  end

  test "Nothing loaded yet", ctx do
    screens = screens(ctx)
    assert screens.file_count == 0
    assert screens.tabs == []
    assert screens.notes == []
  end

  test "Notes come back after a reload", ctx do
    names = for n <- 1..95, do: "page-#{String.pad_leading("#{n}", 2, "0")}.html"
    loaded!(ctx, names, ignored_file_names: ["notes.txt", "logo.svg"])

    # Read afresh, as a board opened again does.
    screens = screens(ctx)
    assert screens.file_count == 80

    assert screens.notes == [
             "Loaded the first 80 of 95 files.",
             "Ignored notes.txt and logo.svg: only HTML, screenshots and .zip files are used."
           ]
  end

  test "A split that stopped early keeps its note", ctx do
    loaded!(ctx, ["app.html"], interactive: true)
    pages = for n <- 1..9, do: {if(n < 5, do: "Host", else: "Member"), "Page #{n}"}
    split!(ctx, pages, role_count: 2, timed_out: true)

    screens = screens(ctx)
    assert screens.is_split == true
    assert screens.page_count == 9

    assert screens.notes == [
             "Split app.html into 9 pages across 2 roles (stopped after 4 minutes). Each tab above is one page."
           ]
  end

  test "Undo split restores the original file", ctx do
    loaded!(ctx, ["app.html"], interactive: true)
    split!(ctx, for(n <- 1..12, do: {nil, "Page #{n}"}))

    dispatch!(%UndoSplit{
      project_id: ctx.project_id,
      prototype_id: ctx.prototype_id,
      undone_by: ctx.account,
      undone_at: @at
    })

    :ok = PrototypePage.remove!(ctx.prototype_id)

    screens = screens(ctx)
    assert screens.is_split == false
    assert screens.file_count == 1
    assert tabs(screens) == [{"app.html", :live_html}]
    assert screens.notes == []
  end

  test "A new load replaces an earlier split", ctx do
    loaded!(ctx, ["app.html"], interactive: true)
    split!(ctx, for(n <- 1..12, do: {nil, "Page #{n}"}))
    loaded!(ctx, ["a.html", "b.html"])
    :ok = PrototypePage.remove!(ctx.prototype_id)

    screens = screens(ctx)
    assert screens.file_count == 2
    assert screens.is_split == false
    assert tabs(screens) == [{"a.html", :static_html}, {"b.html", :static_html}]
  end
end
