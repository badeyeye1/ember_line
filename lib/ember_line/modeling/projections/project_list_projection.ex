defmodule EmberLine.Modeling.Projections.ProjectListProjection do
  @moduledoc """
  Projection ProjectListProjection: builds the ProjectList read model.

  Strongly consistent, so a command dispatched with `consistency: :strong`
  returns after the list is updated.
  """
  use Commanded.Projections.Ecto,
    application: EmberLine.CommandedApp,
    repo: EmberLine.Repo,
    name: "ProjectListProjection",
    consistency: :strong

  import Ecto.Query, only: [from: 2]

  alias EmberLine.Modeling.Project.{ProjectCreated, ProjectDeleted}
  alias EmberLine.Modeling.Projections.ProjectList

  # "add a project row with its name, description, stack, storage mode and source"
  project(%ProjectCreated{} = event, _metadata, fn multi ->
    Ecto.Multi.insert_all(
      multi,
      :project_list,
      ProjectList,
      [
        %{
          project_id: event.project_id,
          name: event.name,
          description: event.description,
          stack: event.stack,
          persistence_mode: event.persistence_mode,
          source_type: event.source_type,
          is_sample: false,
          created_at: event.created_at,
          created_by_id: event.created_by,
          workspace_id: event.workspace_id
        }
      ],
      on_conflict: :nothing,
      conflict_target: [:project_id]
    )
  end)

  # "remove the project's row"
  project(%ProjectDeleted{project_id: project_id}, _metadata, fn multi ->
    Ecto.Multi.delete_all(
      multi,
      :project_list,
      from(row in ProjectList, where: row.project_id == ^project_id)
    )
  end)
end
