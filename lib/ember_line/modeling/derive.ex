defmodule EmberLine.Modeling.Derive do
  @moduledoc """
  Derive model (slice derive-model). Pressing it checks the rules at once,
  in the model's order (no such project, not an editor, nothing loaded,
  stack not in the list, too large), then records a DerivationRun and
  starts the background job (`EmberLine.Modeling.Derive.Job`) in one
  transaction. Stop cancels the job.

  The board shows the project's latest run and hears about changes on
  `topic/1`.
  """

  import Ecto.Query, only: [from: 2]

  alias EmberLine.Accounts.Workspace
  alias EmberLine.Modeling.{Derivation, DerivationRun}
  alias EmberLine.Modeling.Derive.{Input, Job}
  alias EmberLine.Modeling.Projections.{ProjectList, PrototypeScreens}
  alias EmberLine.Repo

  @doc "Starts a derive for the project, or says why it can't."
  @spec start(Ecto.UUID.t(), Ecto.UUID.t() | nil) :: {:ok, DerivationRun.t()} | {:error, atom()}
  def start(project_id, account_id) do
    with {:ok, project} <- project(project_id),
         :ok <- allowed(account_id),
         {:ok, screens} <- loaded(project_id),
         {:ok, _stack} <- stack(project),
         {:ok, input} <- input(project_id, screens) do
      derivation_id = Ecto.UUID.generate()

      message =
        "Claude is reading #{input.reading} and mapping screens, slices and events. This takes a minute or two."

      {:ok, run} =
        Repo.transaction(fn ->
          now = DateTime.utc_now()
          opts = [authorize?: false]
          run = DerivationRun.start!(derivation_id, project_id, message, account_id, now, opts)

          %{derivation_id: derivation_id, project_id: project_id, account_id: account_id}
          |> Job.new()
          |> Oban.insert!()

          run
        end)

      broadcast(run)
      {:ok, run}
    end
  end

  @doc "Stops a running derive: the job is cancelled and nothing is recorded."
  @spec stop(Ecto.UUID.t()) :: {:ok, DerivationRun.t()}
  def stop(derivation_id) do
    run = Ash.get!(DerivationRun, derivation_id, authorize?: false)

    if run.status == :running do
      Oban.cancel_all_jobs(
        from(j in Oban.Job,
          where: j.worker == ^inspect(Job),
          where: fragment("?->>'derivation_id' = ?", j.args, ^derivation_id)
        )
      )

      finish(run, :stopped, "Stopped.")
    else
      {:ok, run}
    end
  end

  @doc "The project's latest run, or nil."
  def latest_run(project_id) do
    {:ok, run} = DerivationRun.latest_for_project(project_id, authorize?: false)
    run
  end

  @doc "Where the board hears about the project's runs."
  def topic(project_id), do: "derivations:" <> project_id

  @doc "Ends a run with its status and the board's sentence, and tells the board."
  def finish(run, status, message) do
    run = DerivationRun.finish!(run, status, message, authorize?: false)
    broadcast(run)
    {:ok, run}
  end

  @doc "The project's stack from ProjectCreated, or Other when it has none."
  def stack(%{stack: nil}), do: {:ok, "Other"}

  def stack(%{stack: stack}) do
    if stack in Workspace.stacks(), do: {:ok, stack}, else: {:error, :stack_not_listed}
  end

  @doc "What Claude is sent for the project, unless it's too large."
  def input(project_id, screens) do
    earlier =
      case Derivation.latest_for_project(project_id, authorize?: false) do
        {:ok, %{slices: slices}} -> slices
        {:ok, nil} -> []
      end

    input = Input.build(screens, earlier)
    if Input.too_large?(input), do: {:error, :too_large_to_derive}, else: {:ok, input}
  end

  @doc """
  The safety net for one derive: an outline with more slices than the
  EMBERLINE_MAX_DERIVE_SLICES setting (default 400) is rejected before
  it's stored.
  """
  def check_size(%{"slices" => slices}) do
    max = max_slices()
    count = length(slices)
    if count > max, do: {:error, {:outline_too_big, count, max}}, else: :ok
  end

  @doc "The most slices one derive can take: the EMBERLINE_MAX_DERIVE_SLICES setting."
  def max_slices,
    do: :ember_line |> Application.get_env(__MODULE__, []) |> Keyword.get(:max_slices, 400)

  @doc "The project's row, unless it doesn't exist or was deleted."
  def project(project_id) do
    case Ash.get(ProjectList, project_id, authorize?: false) do
      {:ok, project} -> {:ok, project}
      {:error, _not_found} -> {:error, :project_not_found}
    end
  end

  # Until Member roles exist, "allowed" means signed in.
  defp allowed(nil), do: {:error, :derive_not_allowed}
  defp allowed(_account_id), do: :ok

  defp loaded(project_id) do
    case PrototypeScreens.for_project!(project_id) do
      %{prototype_id: nil} -> {:error, :nothing_to_derive}
      screens -> {:ok, screens}
    end
  end

  defp broadcast(run),
    do: Phoenix.PubSub.broadcast(EmberLine.PubSub, topic(run.project_id), {:derivation_run, run})
end
