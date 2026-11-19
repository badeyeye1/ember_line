defmodule EmberLine.Modeling.Prototypes do
  @moduledoc """
  Loads a prototype (slice load-prototype): dispatches LoadPrototype with
  what `EmberLine.Modeling.Intake` read, then stores the kept files under the
  prototype id the aggregate settled on (a project's prototype keeps its id
  when it's loaded again).
  """

  alias EmberLine.CommandedApp
  alias EmberLine.Modeling.{Intake, PrototypeFile}
  alias EmberLine.Modeling.Project.{LoadPrototype, PrototypeLimits}

  @type loaded :: %{
          prototype_id: Ecto.UUID.t(),
          file_count: non_neg_integer(),
          skipped_count: non_neg_integer(),
          ignored_file_names: [String.t()]
        }

  @spec load(Ecto.UUID.t(), :files | :paste, Intake.result(), Ecto.UUID.t()) ::
          {:ok, loaded()} | {:error, term()}
  def load(project_id, source, intake, account_id) do
    command = %LoadPrototype{
      prototype_id: Ecto.UUID.generate(),
      project_id: project_id,
      source: source,
      file_names: intake.file_names,
      unreadable_file_names: intake.unreadable_file_names,
      ignored_file_names: intake.ignored_file_names,
      interactive: intake.interactive,
      too_large_file_names: intake.too_large_file_names,
      total_bytes: intake.total_bytes,
      loaded_by: account_id,
      loaded_at: DateTime.utc_now() |> DateTime.truncate(:second)
    }

    with {:ok, %{prototype_id: prototype_id}} <-
           CommandedApp.dispatch(command, consistency: :strong, returning: :aggregate_state) do
      :ok = PrototypeFile.replace!(prototype_id, intake.files)
      {file_names, skipped_count} = PrototypeLimits.kept(intake.file_names)

      {:ok,
       %{
         prototype_id: prototype_id,
         file_count: length(file_names),
         skipped_count: skipped_count,
         ignored_file_names: intake.ignored_file_names
       }}
    end
  end
end
