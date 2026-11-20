defmodule EmberLine.Modeling.Slices do
  @moduledoc """
  Adding slices to a project's board. AddSlice follows the same rules
  whether a person (add-slice) or the create-derived-slices automation sends
  it. The rules that need other streams are checked here, before dispatch,
  because the Slice aggregate sees only its own stream: the project exists,
  and the board has room (at most 150 slices). A slice id that already has
  a history records nothing and isn't an error (the aggregate decides that).
  """

  import Ecto.Query, only: [from: 2]

  alias EmberLine.CommandedApp
  alias EmberLine.Modeling.Projections.{AddedSlices, ProjectList}
  alias EmberLine.Modeling.Slice.AddSlice
  alias EmberLine.Repo

  @max_slices 150

  @doc "The most slices a board can hold."
  def max_slices, do: @max_slices

  @doc "Adds the slice, or says why it can't be added."
  @spec add(AddSlice.t()) :: :ok | {:error, :project_not_found | :board_full}
  def add(%AddSlice{} = command) do
    cond do
      not project?(command.project_id) -> {:error, :project_not_found}
      added?(command.slice_id) -> :ok
      count(command.project_id) >= @max_slices -> {:error, :board_full}
      true -> CommandedApp.dispatch(command, consistency: :strong)
    end
  end

  @doc "How many slices the project's board has."
  @spec count(Ecto.UUID.t()) :: non_neg_integer()
  def count(project_id),
    do: Repo.aggregate(from(a in AddedSlices, where: a.project_id == ^project_id), :count)

  defp project?(project_id),
    do: match?({:ok, _project}, Ash.get(ProjectList, project_id, authorize?: false))

  defp added?(slice_id), do: Repo.exists?(from(a in AddedSlices, where: a.slice_id == ^slice_id))
end
