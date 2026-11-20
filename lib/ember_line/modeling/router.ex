defmodule EmberLine.Modeling.Router do
  @moduledoc "Routes Project and Slice commands to their aggregates. Each slice adds its dispatch here."
  use Commanded.Commands.Router

  alias EmberLine.Modeling.{Project, Slice}

  alias EmberLine.Modeling.Project.{
    CreateProject,
    DeleteProject,
    DeriveModel,
    LoadPrototype,
    SplitPrototype,
    UndoSplit
  }

  alias EmberLine.Modeling.Slice.AddSlice

  identify Project, by: :project_id, prefix: "project-"
  identify Slice, by: :slice_id, prefix: "slice-"

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

  # derive-model
  dispatch DeriveModel, to: Project

  # create-derived-slices
  dispatch AddSlice, to: Slice
end
