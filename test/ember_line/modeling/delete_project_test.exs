defmodule EmberLine.Modeling.DeleteProjectTest do
  @moduledoc "Slice delete-project: one test per scenario in docs/model.json."
  use EmberLine.DataCase, async: false
  use EmberLine.EventModelCase

  alias Commanded.Serialization.JsonDecoder
  alias EmberLine.Modeling.Errors
  alias EmberLine.Modeling.Project
  alias EmberLine.Modeling.Project.{CreateProject, DeleteProject, ProjectCreated, ProjectDeleted}
  alias EmberLine.Modeling.Projections.ProjectList

  @created_at ~U[2026-11-18 10:00:00Z]
  @deleted_at ~U[2026-11-19 09:30:00Z]

  setup do
    %{
      p1: Ecto.UUID.generate(),
      u1: Ecto.UUID.generate(),
      u2: Ecto.UUID.generate(),
      workspace: Ecto.UUID.generate()
    }
  end

  defp created(ctx, fields \\ []) do
    struct!(
      ProjectCreated,
      Map.merge(
        %{
          project_id: ctx.p1,
          name: "Emberline",
          source_type: :new,
          created_by: ctx.u1,
          workspace_id: ctx.workspace,
          created_at: @created_at
        },
        Map.new(fields)
      )
    )
  end

  defp delete(ctx, fields) do
    struct!(
      DeleteProject,
      Map.merge(
        %{project_id: ctx.p1, deleted_by: ctx.u1, confirmed: true, deleted_at: @deleted_at},
        Map.new(fields)
      )
    )
  end

  defp deleted(ctx, fields) do
    struct!(
      ProjectDeleted,
      Map.merge(
        %{project_id: ctx.p1, deleted_by: ctx.u1, deleted_at: @deleted_at},
        Map.new(fields)
      )
    )
  end

  test "Confirmed delete removes the project", ctx do
    assert_decides(
      Project,
      [created(ctx)],
      delete(ctx, deleted_by: ctx.u1, confirmed: true),
      [deleted(ctx, deleted_by: ctx.u1)]
    )

    # Through the Commanded app: the project leaves the ProjectList read model.
    dispatch!(%CreateProject{
      project_id: ctx.p1,
      name: "Emberline",
      source_type: :new,
      created_by: ctx.u1,
      workspace_id: ctx.workspace,
      created_at: @created_at
    })

    assert [%{project_id: p1}] = ProjectList.for_workspace!(ctx.workspace)
    assert p1 == ctx.p1

    dispatch!(delete(ctx, confirmed: true))

    assert ProjectList.for_workspace!(ctx.workspace) == []
  end

  test "First click only asks to confirm", ctx do
    assert_decides(
      Project,
      [created(ctx, name: "Emberline")],
      delete(ctx, deleted_by: ctx.u1, confirmed: false),
      {:error, {:confirm_delete, "Emberline"}}
    )

    assert Errors.message({:confirm_delete, "Emberline"}) ==
             "Click Delete again to delete Emberline. This can't be undone."
  end

  @tag skip:
         "Needs Member roles (invite-members / change-role slices). Until then the rule is: signed in, see the deletedBy test below"
  test "Commenters and viewers cannot delete" do
  end

  test "Project does not exist", ctx do
    assert_decides(
      Project,
      [],
      delete(ctx, project_id: Ecto.UUID.generate(), deleted_by: ctx.u1, confirmed: true),
      {:error, :project_not_found}
    )

    assert Errors.message(:project_not_found) == "That project doesn't exist."
  end

  test "Deleted twice", ctx do
    assert_decides(
      Project,
      [created(ctx), deleted(ctx, deleted_by: ctx.u1)],
      delete(ctx, deleted_by: ctx.u2, confirmed: true),
      {:error, :project_not_found}
    )
  end

  # Not a model scenario: the "only signed-in users delete projects" rule,
  # enforced on the write side until Member roles exist.
  test "a command without deletedBy is NotAllowed", ctx do
    assert_decides(
      Project,
      [created(ctx)],
      delete(ctx, deleted_by: nil, confirmed: true),
      {:error, :delete_not_allowed}
    )

    assert Errors.message(:delete_not_allowed) ==
             "Only editors and admins can delete a project."
  end

  # Not a model scenario: ProjectDeleted survives the EventStore's JSON round trip.
  test "ProjectDeleted decodes its deletedAt", ctx do
    json = ctx |> deleted(deleted_by: ctx.u1) |> Jason.encode!() |> Jason.decode!()

    event =
      JsonDecoder.decode(%ProjectDeleted{
        project_id: json["project_id"],
        deleted_by: json["deleted_by"],
        deleted_at: json["deleted_at"]
      })

    assert event == deleted(ctx, deleted_by: ctx.u1)
  end
end
