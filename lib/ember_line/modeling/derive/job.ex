defmodule EmberLine.Modeling.Derive.Job do
  @moduledoc """
  The derive-model background job: sends the prototype to Claude, stores
  the outline in a Derivation record, dispatches DeriveModel (the aggregate
  checks the rules again) and ends the DerivationRun with the board's
  sentence. A failure ends the run as failed and records nothing. One
  attempt: Derive model is pressed again to retry.
  """
  use Oban.Worker, queue: :derive, max_attempts: 1

  alias EmberLine.CommandedApp
  alias EmberLine.Modeling.{Derivation, DerivationRun, Derive, Errors}
  alias EmberLine.Modeling.Derive.{Claude, Outline}
  alias EmberLine.Modeling.Project.DeriveModel
  alias EmberLine.Modeling.Projections.PrototypeScreens

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"derivation_id" => derivation_id} = args}) do
    run = Ash.get!(DerivationRun, derivation_id, authorize?: false)
    if run.status == :running, do: derive(run, args), else: :ok
  end

  defp derive(run, %{"project_id" => project_id, "account_id" => account_id}) do
    earlier = earlier_slices(project_id)

    result =
      with {:ok, project} <- Derive.project(project_id),
           {:ok, stack} <- Derive.stack(project),
           screens = PrototypeScreens.for_project!(project_id),
           {:ok, input} <- Derive.input(project_id, screens),
           {:ok, text} <- Claude.ask(input.prompt, input.images),
           {:ok, outline} <- Outline.parse(text),
           :ok <- Derive.check_size(outline) do
        record(run, screens, stack, outline, earlier, account_id)
      end

    case result do
      {:ok, message} -> Derive.finish(run, :done, message)
      {:error, :stopped} -> :ok
      {:error, reason} -> Derive.finish(run, :failed, Errors.message(reason))
    end

    :ok
  end

  defp record(run, screens, stack, outline, earlier, account_id) do
    {stored, not_in_new} = Outline.with_ids(outline, earlier)
    derived_at = DateTime.utc_now()

    derivation =
      Derivation.store!(
        run.derivation_id,
        run.project_id,
        stored.app,
        stored.screens,
        stored.streams,
        stored.outcomes,
        stored.slices,
        derived_at,
        authorize?: false
      )

    command = %DeriveModel{
      derivation_id: run.derivation_id,
      project_id: run.project_id,
      prototype_id: screens.prototype_id,
      stack: stack,
      app_name: to_string(stored.app["name"] || ""),
      screen_count: length(stored.screens),
      slice_count: length(stored.slices),
      outcome_count: length(stored.outcomes),
      slice_ids: Enum.map(stored.slices, & &1["id"]),
      not_in_new_outline: not_in_new,
      derived_by: account_id,
      derived_at: DateTime.truncate(derived_at, :second)
    }

    # Stop pressed while Claude was answering: nothing is recorded.
    with :ok <- still_running(run),
         :ok <- CommandedApp.dispatch(command, consistency: :strong) do
      {:ok, done_message(command)}
    else
      error ->
        Ash.destroy!(derivation, authorize?: false)
        error
    end
  end

  defp still_running(run) do
    case Ash.get!(DerivationRun, run.derivation_id, authorize?: false) do
      %{status: :running} -> :ok
      _stopped -> {:error, :stopped}
    end
  end

  defp earlier_slices(project_id) do
    case Derivation.latest_for_project(project_id, authorize?: false) do
      {:ok, %{slices: slices}} -> slices
      {:ok, nil} -> []
    end
  end

  defp done_message(%DeriveModel{} = c) do
    mapped = "Mapped #{count(c.screen_count, "screen")} into #{count(c.slice_count, "slice")}."

    case length(c.not_in_new_outline) do
      0 -> mapped
      1 -> mapped <> " 1 slice from before isn't in the new model: review it on the board."
      k -> mapped <> " #{k} slices from before aren't in the new model: review them on the board."
    end
  end

  defp count(1, noun), do: "1 #{noun}"
  defp count(n, noun), do: "#{n} #{noun}s"
end
