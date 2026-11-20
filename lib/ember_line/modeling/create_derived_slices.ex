defmodule EmberLine.Modeling.CreateDerivedSlices do
  @moduledoc """
  The create-derived-slices automation: after a derive, adds the outline's
  slices to the board one by one, in the outline's order, from the
  SlicesToCreate list. Started by `SlicesToCreateProjection` when it lists a
  derive's slices.

  Each AddSlice carries every value SliceAdded records, position included,
  from the stored outline. A restart picks up the slices still on the list.
  If the project reaches its safety ceiling, the rest aren't added and the
  derive's status says how many; if the project is gone, the rest are
  dropped with no message.
  """
  use Oban.Worker, queue: :derive, max_attempts: 3

  alias EmberLine.Modeling.{DerivationRun, Derive, Slices}
  alias EmberLine.Modeling.Projections.SlicesToCreate
  alias EmberLine.Modeling.Slice.AddSlice

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"project_id" => project_id, "derivation_id" => derivation_id}}) do
    project_id
    |> SlicesToCreate.for_project!(authorize?: false)
    |> Enum.filter(&(&1.derivation_id == derivation_id))
    |> add_all(derivation_id)
  end

  defp add_all([], _derivation_id), do: :ok

  defp add_all([row | rest] = rows, derivation_id) do
    case Slices.add(command(row)) do
      :ok -> add_all(rest, derivation_id)
      {:error, :too_many_slices} -> ceiling(derivation_id, length(rows))
      # The project is gone, and its board with it: no message.
      {:error, :project_not_found} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp command(row) do
    %AddSlice{
      slice_id: row.slice_id,
      project_id: row.project_id,
      name: row.name,
      pattern: row.pattern,
      screen_id: row.screen_id,
      position: row.position,
      feature_id: row.feature_id,
      produces: row.produces,
      reads: row.reads,
      command_name: row.command_name,
      read_model_name: row.read_model_name,
      projection_name: ""
    }
  end

  # The sentence goes after derive-model's done sentence, so wait for it.
  defp ceiling(derivation_id, left) do
    case Ash.get(DerivationRun, derivation_id, authorize?: false) do
      {:ok, %{status: :running}} ->
        {:snooze, 2}

      {:ok, run} ->
        {:ok, _run} = Derive.finish(run, run.status, run.message <> " " <> not_added(left))
        :ok

      {:error, _not_found} ->
        :ok
    end
  end

  defp not_added(n) do
    limit = "this project is at its limit of #{Slices.format_count(Slices.max_slices())} slices."
    if n == 1, do: "1 slice wasn't added: " <> limit, else: "#{n} slices weren't added: " <> limit
  end
end
