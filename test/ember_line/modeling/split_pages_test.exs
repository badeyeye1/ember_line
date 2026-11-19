defmodule EmberLine.Modeling.SplitPagesTest do
  @moduledoc "Slice split-pages: one test per scenario in docs/model.json."
  use EmberLine.DataCase, async: false
  use EmberLine.EventModelCase

  alias Commanded.Serialization.JsonDecoder
  alias EmberLine.Modeling.{Errors, PrototypePage, Prototypes}
  alias EmberLine.Modeling.Project

  alias EmberLine.Modeling.Project.{
    ProjectCreated,
    PrototypeLoaded,
    PrototypeSplitIntoPages,
    SplitPrototype,
    SplitUndone
  }

  @at ~U[2026-11-19 10:00:00Z]
  @not_interactive "Load an interactive HTML prototype first: only those can be split into pages."

  setup do
    %{pr: Ecto.UUID.generate(), p1: Ecto.UUID.generate(), u1: Ecto.UUID.generate()}
  end

  defp created(ctx), do: %ProjectCreated{project_id: ctx.pr, name: "Emberline"}

  defp loaded(ctx, fields \\ []) do
    struct!(
      PrototypeLoaded,
      Map.merge(
        %{
          prototype_id: ctx.p1,
          project_id: ctx.pr,
          source: :files,
          file_names: ["app.html"],
          file_count: 1,
          skipped_count: 0,
          ignored_file_names: [],
          interactive: true,
          loaded_by: ctx.u1,
          loaded_at: @at
        },
        Map.new(fields)
      )
    )
  end

  defp split(ctx, fields) do
    struct!(
      SplitPrototype,
      Map.merge(
        %{
          project_id: ctx.pr,
          prototype_id: ctx.p1,
          found_page_count: 12,
          role_count: 3,
          timed_out: false,
          split_by: ctx.u1,
          split_at: @at
        },
        Map.new(fields)
      )
    )
  end

  defp split_into_pages(ctx, fields) do
    struct!(
      PrototypeSplitIntoPages,
      Map.merge(
        %{
          project_id: ctx.pr,
          prototype_id: ctx.p1,
          page_count: 12,
          role_count: 3,
          skipped_count: 0,
          timed_out: false,
          split_by: ctx.u1,
          split_at: @at
        },
        Map.new(fields)
      )
    )
  end

  defp undone(ctx),
    do: %SplitUndone{project_id: ctx.pr, prototype_id: ctx.p1, undone_by: ctx.u1, undone_at: @at}

  defp rejects(given, command, message) do
    state = Enum.reduce(given, %Project{}, &Project.apply(&2, &1))
    assert {:error, reason} = Project.execute(state, command)
    assert Errors.message(reason) == message
  end

  # The board's sentence for the event, about the loaded file.
  defp says(event), do: Prototypes.split_note("app.html", event)

  test "Split an interactive prototype", ctx do
    event = split_into_pages(ctx, page_count: 12, role_count: 3)
    assert_decides(Project, [created(ctx), loaded(ctx)], split(ctx, []), [event])

    assert says(event) ==
             "Split app.html into 12 pages across 3 roles. Each tab above is one page."
  end

  test "No prototype loaded", ctx do
    rejects([created(ctx)], split(ctx, []), @not_interactive)
  end

  test "Only static pages loaded", ctx do
    static = loaded(ctx, file_names: ["a.html", "b.html"], file_count: 2, interactive: false)
    rejects([created(ctx), static], split(ctx, []), @not_interactive)
  end

  test "No separate pages found", ctx do
    rejects(
      [created(ctx), loaded(ctx)],
      split(ctx, found_page_count: 0, role_count: 0),
      "No separate pages found. Derive the model from the whole file instead."
    )
  end

  test "Prototype does not respond", ctx do
    rejects(
      [created(ctx), loaded(ctx)],
      split(ctx, found_page_count: 0, role_count: 0, timed_out: true),
      "The prototype didn't respond while it was being split. Reload it and try again."
    )
  end

  test "Time runs out after some pages were found", ctx do
    event = split_into_pages(ctx, page_count: 9, role_count: 2, timed_out: true)

    assert_decides(
      Project,
      [created(ctx), loaded(ctx)],
      split(ctx, found_page_count: 9, role_count: 2, timed_out: true),
      [event]
    )

    assert says(event) ==
             "Split app.html into 9 pages across 2 roles (stopped after 4 minutes). Each tab above is one page."
  end

  test "Page limit reached", ctx do
    event = split_into_pages(ctx, page_count: 80, role_count: 3, skipped_count: 40)

    assert_decides(
      Project,
      [created(ctx), loaded(ctx)],
      split(ctx, found_page_count: 120),
      [event]
    )

    assert says(event) ==
             "Split app.html into 80 pages across 3 roles (stopped at 80). Each tab above is one page."

    # The first 80 pages in the order found are kept.
    found = for n <- 1..120, do: page(n)
    assert Enum.map(Prototypes.kept_pages(found), & &1.title) == Enum.map(1..80, &"Page #{&1}")
  end

  test "Already split", ctx do
    rejects(
      [created(ctx), loaded(ctx), split_into_pages(ctx, [])],
      split(ctx, []),
      "This prototype is already split. Undo the split first."
    )
  end

  test "Splitting again after an undo", ctx do
    assert_decides(
      Project,
      [created(ctx), loaded(ctx), split_into_pages(ctx, []), undone(ctx)],
      split(ctx, found_page_count: 14),
      [split_into_pages(ctx, page_count: 14)]
    )

    # ... and the stored pages for p-1 are replaced.
    :ok = PrototypePage.replace!(ctx.p1, [page(1), page(2)])
    :ok = PrototypePage.replace!(ctx.p1, [page(3)])
    assert [%{title: "Page 3", position: 1}] = PrototypePage.for_prototype!(ctx.p1)
  end

  test "A new load clears the split", ctx do
    reload = loaded(ctx, file_names: ["app-v2.html"])

    assert_decides(
      Project,
      [created(ctx), loaded(ctx), split_into_pages(ctx, []), reload],
      split(ctx, found_page_count: 15),
      [split_into_pages(ctx, page_count: 15)]
    )
  end

  test "No such project", ctx do
    rejects([], split(ctx, []), "That project doesn't exist.")
  end

  @tag skip:
         "Needs Member roles (MemberRoleChanged, slice change-role). Until then any signed-in member may split."
  test "Viewers and commenters can't split (once roles exist)" do
  end

  test "A prototype with no role picker", ctx do
    event = split_into_pages(ctx, page_count: 5, role_count: 0)

    assert_decides(
      Project,
      [created(ctx), loaded(ctx)],
      split(ctx, found_page_count: 5, role_count: 0),
      [event]
    )

    assert says(event) == "Split app.html into 5 pages. Each tab above is one page."
  end

  test "Only one role", ctx do
    event = split_into_pages(ctx, page_count: 5, role_count: 1)

    assert_decides(
      Project,
      [created(ctx), loaded(ctx)],
      split(ctx, found_page_count: 5, role_count: 1),
      [event]
    )

    assert says(event) == "Split app.html into 5 pages across 1 role. Each tab above is one page."
  end

  test "Only one page found", ctx do
    event = split_into_pages(ctx, page_count: 1, role_count: 2)

    assert_decides(
      Project,
      [created(ctx), loaded(ctx)],
      split(ctx, found_page_count: 1, role_count: 2),
      [event]
    )

    assert says(event) == "Split app.html into 1 page across 2 roles. Each tab above is one page."
  end

  # --- not model scenarios ----------------------------------------------------

  test "a deleted project doesn't exist", ctx do
    deleted = %EmberLine.Modeling.Project.ProjectDeleted{project_id: ctx.pr, deleted_at: @at}
    rejects([created(ctx), loaded(ctx), deleted], split(ctx, []), "That project doesn't exist.")
  end

  test "a command without splitBy is refused", ctx do
    rejects(
      [created(ctx), loaded(ctx)],
      split(ctx, split_by: nil),
      "Only editors can split a prototype."
    )
  end

  test "the loaded prototype's id is used, whatever the command says", ctx do
    other = Ecto.UUID.generate()

    assert_decides(
      Project,
      [created(ctx), loaded(ctx)],
      split(ctx, prototype_id: other),
      [split_into_pages(ctx, [])]
    )
  end

  test "the events survive the event store's JSON round trip", ctx do
    for event <- [split_into_pages(ctx, timed_out: true), undone(ctx)] do
      json = event |> Jason.encode!() |> Jason.decode!(keys: :atoms)
      assert JsonDecoder.decode(struct(event.__struct__, json)) == event
    end
  end

  defp page(n),
    do: %{title: "Page #{n}", role: "Host", route: "#p#{n}", html: "<p>#{n}</p>"}
end
