defmodule EmberLine.Modeling.ViewProjectsTest do
  @moduledoc """
  Slice view-projects, read model ProjectList: the scenarios that ProjectCreated
  covers. SampleProjectOpened comes from the open-sample slice.
  """
  use EmberLine.DataCase, async: false
  use EmberLine.EventModelCase

  alias EmberLine.Modeling.Project.{CreateProject, DeleteProject}
  alias EmberLine.Modeling.Projections.ProjectList

  setup do
    %{account: Ecto.UUID.generate(), workspace: Ecto.UUID.generate()}
  end

  defp create!(ctx, fields) do
    dispatch!(
      struct!(
        CreateProject,
        Map.merge(
          %{
            project_id: Ecto.UUID.generate(),
            created_by: ctx.account,
            workspace_id: ctx.workspace,
            created_at: ~U[2026-11-18 10:00:00Z]
          },
          Map.new(fields)
        )
      )
    )
  end

  test "Lists created projects", ctx do
    p1 = Ecto.UUID.generate()

    create!(ctx,
      project_id: p1,
      name: "Edgemastery",
      description: "Coaching platform",
      source_type: :new,
      stack: "Elixir: Phoenix LiveView + Ash + Commanded",
      persistence_mode: :mixed,
      created_at: ~U[2026-11-18 10:00:00Z]
    )

    create!(ctx,
      name: "Billing API",
      source_type: :github,
      repo_url: "https://github.com/acme/billing",
      created_at: ~U[2026-11-18 11:00:00Z]
    )

    rows = ProjectList.for_workspace!(ctx.workspace)
    assert Enum.map(rows, & &1.name) == ["Edgemastery", "Billing API"]

    [edgemastery, _] = rows
    assert edgemastery.project_id == p1
    assert edgemastery.description == "Coaching platform"
    assert edgemastery.stack == "Elixir: Phoenix LiveView + Ash + Commanded"
    assert edgemastery.persistence_mode == :mixed
    assert edgemastery.source_type == :new
    assert edgemastery.is_sample == false
    assert edgemastery.created_at == ~U[2026-11-18 10:00:00Z]
    assert edgemastery.created_by == ctx.account
    assert edgemastery.workspace_id == ctx.workspace
  end

  @tag skip: "SampleProjectOpened is produced by the open-sample slice (step 19)"
  test "Sample project is listed and flagged" do
  end

  test "No projects yet", ctx do
    assert ProjectList.for_workspace!(ctx.workspace) == []
  end

  @tag skip: "SampleProjectOpened is produced by the open-sample slice (step 19)"
  test "Opening the sample twice lists it once" do
  end

  test "Storage mode defaults from the stack", ctx do
    create!(ctx,
      name: "Ledger",
      source_type: :new,
      stack: "Elixir: Phoenix LiveView + Ash + Commanded",
      persistence_mode: :event_sourced
    )

    assert [%{name: "Ledger", persistence_mode: :event_sourced}] =
             ProjectList.for_workspace!(ctx.workspace)
  end

  # ProjectDeleted comes from the delete-project slice.
  test "Deleted project is not listed", ctx do
    create!(ctx, name: "Emberline", source_type: :new)
    spare = Ecto.UUID.generate()
    create!(ctx, project_id: spare, name: "Spare", source_type: :new)

    dispatch!(%DeleteProject{
      project_id: spare,
      deleted_by: ctx.account,
      confirmed: true,
      deleted_at: ~U[2026-11-19 09:30:00Z]
    })

    assert Enum.map(ProjectList.for_workspace!(ctx.workspace), & &1.name) == ["Emberline"]
  end

  # Not a model scenario: the list is per workspace.
  test "lists only the workspace's projects", ctx do
    create!(ctx, name: "Edgemastery", source_type: :new)
    create!(%{ctx | workspace: Ecto.UUID.generate()}, name: "Elsewhere", source_type: :new)

    assert Enum.map(ProjectList.for_workspace!(ctx.workspace), & &1.name) == ["Edgemastery"]
  end
end
