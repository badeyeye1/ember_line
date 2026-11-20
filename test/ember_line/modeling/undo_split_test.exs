defmodule EmberLine.Modeling.UndoSplitTest do
  @moduledoc "Slice undo-split: one test per scenario in docs/model.json."
  use EmberLine.DataCase, async: false
  use EmberLine.EventModelCase

  alias EmberLine.Modeling.{Errors, Intake, PrototypePage, Prototypes}
  alias EmberLine.Modeling.Project

  alias EmberLine.Modeling.Project.{
    CreateProject,
    ProjectCreated,
    ProjectDeleted,
    PrototypeLoaded,
    PrototypeSplitIntoPages,
    SplitUndone,
    UndoSplit
  }

  @at ~U[2026-11-19 10:00:00Z]
  @nothing_to_undo "There's no split to undo."

  setup do
    %{pr: Ecto.UUID.generate(), p1: Ecto.UUID.generate(), u1: Ecto.UUID.generate()}
  end

  defp created(ctx), do: %ProjectCreated{project_id: ctx.pr, name: "Emberline"}

  defp loaded(ctx, file_name \\ "app.html") do
    %PrototypeLoaded{
      prototype_id: ctx.p1,
      project_id: ctx.pr,
      source: :files,
      file_names: [file_name],
      file_count: 1,
      skipped_count: 0,
      ignored_file_names: [],
      interactive: true,
      loaded_by: ctx.u1,
      loaded_at: @at
    }
  end

  defp split(ctx) do
    %PrototypeSplitIntoPages{
      project_id: ctx.pr,
      prototype_id: ctx.p1,
      page_count: 12,
      role_count: 3,
      skipped_count: 0,
      timed_out: false,
      split_by: ctx.u1,
      split_at: @at
    }
  end

  defp undo(ctx, fields \\ []) do
    struct!(
      UndoSplit,
      Map.merge(
        %{project_id: ctx.pr, prototype_id: ctx.p1, undone_by: ctx.u1, undone_at: @at},
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

  test "Undo after split", ctx do
    assert_decides(Project, [created(ctx), loaded(ctx), split(ctx)], undo(ctx), [undone(ctx)])
    assert Prototypes.undo_note("app.html") == "Undid the split. The tabs show app.html again."

    # ... and the stored pages for p-1 are removed, through the Commanded app.
    dispatch!(%CreateProject{
      project_id: ctx.pr,
      name: "Emberline",
      source_type: :new,
      created_by: ctx.u1,
      created_at: @at
    })

    app = Intake.paste(~s(<a href="#b">B</a><section id="b"></section>))
    {:ok, %{prototype_id: p1}} = Prototypes.load(ctx.pr, :paste, app, ctx.u1)
    pages = for n <- 1..12, do: %{title: "Page #{n}", role: "", route: "#p#{n}", html: "<p></p>"}
    {:ok, _split} = Prototypes.split(ctx.pr, p1, pages, 12, 0, false, ctx.u1)
    assert length(PrototypePage.for_prototype!(p1)) == 12

    assert {:ok, %SplitUndone{prototype_id: ^p1}} = Prototypes.undo_split(ctx.pr, p1, ctx.u1)
    assert PrototypePage.for_prototype!(p1) == []
  end

  test "Nothing was split", ctx do
    rejects([created(ctx), loaded(ctx)], undo(ctx), @nothing_to_undo)
  end

  test "No prototype", ctx do
    rejects([created(ctx)], undo(ctx), @nothing_to_undo)
  end

  test "Undo twice", ctx do
    rejects([created(ctx), loaded(ctx), split(ctx), undone(ctx)], undo(ctx), @nothing_to_undo)
  end

  test "A new load already cleared the split", ctx do
    rejects(
      [created(ctx), loaded(ctx), split(ctx), loaded(ctx, "app-v2.html")],
      undo(ctx),
      @nothing_to_undo
    )
  end

  test "No such project", ctx do
    rejects([], undo(ctx), "That project doesn't exist.")
  end

  @tag skip:
         "Needs Member roles (MemberRoleChanged, slice change-role). Until then any signed-in member may undo."
  test "Viewers and commenters can't undo a split (once roles exist)" do
  end

  # --- not model scenarios ----------------------------------------------------

  test "a deleted project doesn't exist", ctx do
    deleted = %ProjectDeleted{project_id: ctx.pr, deleted_at: @at}

    rejects(
      [created(ctx), loaded(ctx), split(ctx), deleted],
      undo(ctx),
      "That project doesn't exist."
    )
  end

  test "a command without undoneBy is refused", ctx do
    rejects(
      [created(ctx), loaded(ctx), split(ctx)],
      undo(ctx, undone_by: nil),
      "Only editors can undo a split."
    )
  end

  test "the loaded prototype's id is used, whatever the command says", ctx do
    assert_decides(
      Project,
      [created(ctx), loaded(ctx), split(ctx)],
      undo(ctx, prototype_id: Ecto.UUID.generate()),
      [undone(ctx)]
    )
  end
end
