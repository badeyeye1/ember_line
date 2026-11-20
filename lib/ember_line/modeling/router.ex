defmodule EmberLine.Modeling.Router do
  @moduledoc "Routes Project and Slice commands to their aggregates. Each slice adds its dispatch here."
  use Commanded.Commands.Router

  alias EmberLine.Modeling.Project

  alias EmberLine.Modeling.Project.{
    CreateProject,
    DeleteProject,
    LoadPrototype,
    SplitPrototype,
    UndoSplit
  }

  identify Project, by: :project_id, prefix: "project-"

  # create-project
  dispatch CreateProject, to: Project

  # delete-project
  dispatch DeleteProject, to: Project

  # load-prototype
  dispatch LoadPrototype, to: Project

  # split-pages
  dispatch SplitPrototype, to: Project

  # undo-split
  dispatch UndoSplit, to: Project
end
