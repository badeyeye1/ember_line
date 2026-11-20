defmodule EmberLine.Modeling.Slices do
  @moduledoc """
  Adding slices to a project. AddSlice follows the same rules whether a
  person (add-slice) or the create-derived-slices automation sends it. The
  rules that need other streams are checked here, before dispatch, because
  the Slice aggregate sees only its own stream: the project exists, and the
  project is under its safety ceiling (the EMBERLINE_MAX_SLICES setting,
  default 2,000), a guard against runaway automations, not a working limit.
  A slice id that already has a history records nothing and isn't an error
  (the aggregate decides that).
  """

  import Ecto.Query, only: [from: 2]

  alias EmberLine.CommandedApp
  alias EmberLine.Modeling.Projections.{AddedSlices, ProjectList}
  alias EmberLine.Modeling.Slice.AddSlice
  alias EmberLine.Repo

  @doc "The most slices a project can hold: the EMBERLINE_MAX_SLICES setting."
  @spec max_slices() :: pos_integer()
  def max_slices,
    do: :ember_line |> Application.get_env(__MODULE__, []) |> Keyword.get(:max_slices, 2000)

  @doc "Adds the slice, or says why it can't be added."
  @spec add(AddSlice.t()) :: :ok | {:error, :project_not_found | :too_many_slices}
  def add(%AddSlice{} = command) do
    cond do
      not project?(command.project_id) -> {:error, :project_not_found}
      added?(command.slice_id) -> :ok
      count(command.project_id) >= max_slices() -> {:error, :too_many_slices}
      true -> CommandedApp.dispatch(command, consistency: :strong)
    end
  end

  @doc "How many slices the project has."
  @spec count(Ecto.UUID.t()) :: non_neg_integer()
  def count(project_id),
    do: Repo.aggregate(from(a in AddedSlices, where: a.project_id == ^project_id), :count)

  @doc ~S|A count as people read it: 2000 -> "2,000".|
  @spec format_count(non_neg_integer()) :: String.t()
  def format_count(n) do
    n
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/(\d{3})(?=\d)/, "\\1,")
    |> String.reverse()
  end

  defp project?(project_id),
    do: match?({:ok, _project}, Ash.get(ProjectList, project_id, authorize?: false))

  defp added?(slice_id), do: Repo.exists?(from(a in AddedSlices, where: a.slice_id == ^slice_id))
end
