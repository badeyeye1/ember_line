defmodule EmberLine.Modeling.CreateProjectTest do
  @moduledoc "Slice create-project: one test per scenario in docs/model.json."
  use EmberLine.DataCase, async: false
  use EmberLine.EventModelCase

  alias EmberLine.Accounts.Workspace
  alias EmberLine.Modeling.Errors
  alias EmberLine.Modeling.Project
  alias EmberLine.Modeling.Project.{CreateProject, ProjectCreated}
  alias EmberLine.Modeling.Projections.ProjectList

  @at ~U[2026-11-18 10:00:00Z]

  setup do
    %{
      p1: Ecto.UUID.generate(),
      p2: Ecto.UUID.generate(),
      account: Ecto.UUID.generate(),
      workspace: Ecto.UUID.generate()
    }
  end

  defp create(ctx, fields) do
    struct!(
      CreateProject,
      Map.merge(
        %{
          project_id: ctx.p1,
          created_by: ctx.account,
          workspace_id: ctx.workspace,
          created_at: @at
        },
        Map.new(fields)
      )
    )
  end

  defp created(ctx, fields) do
    struct!(
      ProjectCreated,
      Map.merge(
        %{
          project_id: ctx.p1,
          created_by: ctx.account,
          workspace_id: ctx.workspace,
          created_at: @at
        },
        Map.new(fields)
      )
    )
  end

  test "Start fresh project", ctx do
    stack = "Elixir: Phoenix LiveView + Ash + AshCommanded"

    assert_decides(
      Project,
      [],
      create(ctx,
        name: "Edgemastery",
        source_type: :new,
        stack: stack,
        persistence_mode: :event_sourced
      ),
      [
        created(ctx,
          name: "Edgemastery",
          source_type: :new,
          stack: stack,
          persistence_mode: :event_sourced
        )
      ]
    )
  end

  test "GitHub project with branch", ctx do
    assert_decides(
      Project,
      [],
      create(ctx,
        name: "Billing API",
        source_type: :github,
        repo_url: "https://github.com/acme/billing",
        branch: "main"
      ),
      [
        created(ctx,
          name: "Billing API",
          source_type: :github,
          repo_url: "https://github.com/acme/billing",
          branch: "main"
        )
      ]
    )
  end

  test "Name is missing", ctx do
    for blank <- [nil, "", "   "] do
      assert_decides(
        Project,
        [],
        create(ctx, name: blank, source_type: :new),
        {:error, :project_name_required}
      )
    end

    assert Errors.message(:project_name_required) == "Give the project a name."
  end

  test "GitHub source without a repository URL", ctx do
    for blank <- [nil, "", "   "] do
      assert_decides(
        Project,
        [],
        create(ctx, name: "Billing API", source_type: :github, repo_url: blank),
        {:error, :repo_url_required}
      )
    end

    assert Errors.message(:repo_url_required) ==
             "Paste the GitHub repository address, like https://github.com/owner/repo."
  end

  @tag skip:
         "Needs Member roles (invite-members / change-role slices). Until then the rule is: signed in, see the createdBy test below"
  test "Viewer or commenter cannot create" do
  end

  test "Same name as an existing project", ctx do
    # The decision: a second project with the same name is a new stream with its own id.
    assert_decides(
      Project,
      [],
      create(ctx, project_id: ctx.p2, name: "Edgemastery", source_type: :new),
      [created(ctx, project_id: ctx.p2, name: "Edgemastery", source_type: :new)]
    )

    # Both projects exist, told apart by id.
    dispatch!(create(ctx, project_id: ctx.p1, name: "Edgemastery", source_type: :new))
    dispatch!(create(ctx, project_id: ctx.p2, name: "Edgemastery", source_type: :new))

    rows = ProjectList.for_workspace!(ctx.workspace)

    assert Enum.map(rows, &{&1.project_id, &1.name}) |> Enum.sort() ==
             Enum.sort([{ctx.p1, "Edgemastery"}, {ctx.p2, "Edgemastery"}])
  end

  test "Stack isn't one of the listed ones", ctx do
    assert_decides(
      Project,
      [],
      create(ctx,
        name: "Edgemastery",
        source_type: :new,
        stack: "Rails",
        persistence_mode: :event_sourced
      ),
      {:error, :stack_not_listed}
    )

    assert Errors.message(:stack_not_listed) == "Pick a stack from the list."
  end

  test "SourceType isn't one of the listed ones", ctx do
    for source <- [:dropbox, nil] do
      assert_decides(
        Project,
        [],
        create(ctx,
          name: "Edgemastery",
          source_type: source,
          stack: "Other",
          persistence_mode: :event_sourced
        ),
        {:error, :source_type_not_listed}
      )
    end

    assert Errors.message(:source_type_not_listed) ==
             "Pick where the code comes from: start fresh, a folder on this computer, or GitHub."
  end

  # Not a model scenario: every listed stack is accepted.
  test "every listed stack is accepted", ctx do
    for stack <- Workspace.stacks() do
      assert [%ProjectCreated{stack: ^stack}] =
               List.wrap(
                 Project.execute(
                   %Project{},
                   create(ctx, name: "E", source_type: :new, stack: stack)
                 )
               )
    end
  end

  # Not a model scenario: the "only signed-in users create projects" rule,
  # enforced on the write side until Member roles exist.
  test "a command without createdBy is NotAllowed", ctx do
    assert_decides(
      Project,
      [],
      create(ctx, name: "Edgemastery", source_type: :new, created_by: nil),
      {:error, :not_allowed}
    )

    assert Errors.message(:not_allowed) == "Only editors and admins can create projects."
  end

  # Not a model scenario: a repeated dispatch of the same command (a double
  # submit) records the project once.
  test "creating the same projectId twice records one ProjectCreated", ctx do
    given = [created(ctx, name: "Edgemastery", source_type: :new)]
    assert_decides(Project, given, create(ctx, name: "Edgemastery", source_type: :new), [])
  end
end
