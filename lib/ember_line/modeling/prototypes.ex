defmodule EmberLine.Modeling.Prototypes do
  @moduledoc """
  Loads a prototype (slice load-prototype): dispatches LoadPrototype with
  what `EmberLine.Modeling.Intake` read, then stores the kept files under the
  prototype id the aggregate settled on (a project's prototype keeps its id
  when it's loaded again).
  """

  alias EmberLine.CommandedApp
  alias EmberLine.Modeling.{Intake, PrototypeFile, PrototypePage}
  alias EmberLine.Modeling.Project

  alias EmberLine.Modeling.Project.{
    LoadPrototype,
    PrototypeLimits,
    PrototypeSplitIntoPages,
    SplitPrototype,
    SplitUndone,
    UndoSplit
  }

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
      # A new load clears the split.
      :ok = PrototypePage.remove!(prototype_id)
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

  @type page :: %{
          title: String.t(),
          role: String.t() | nil,
          route: String.t() | nil,
          html: String.t()
        }

  @doc """
  Splits the project's prototype into pages (slice split-pages): dispatches
  SplitPrototype with what the browser found, then stores the kept pages.
  `pages` are the pages in the order found (the browser sends at most the
  first 80; `found_page_count` counts them all).
  """
  @spec split(
          Ecto.UUID.t(),
          Ecto.UUID.t(),
          [page()],
          non_neg_integer(),
          non_neg_integer(),
          boolean(),
          Ecto.UUID.t()
        ) ::
          {:ok, PrototypeSplitIntoPages.t()} | {:error, term()}
  def split(project_id, prototype_id, pages, found_page_count, role_count, timed_out, account_id) do
    command = %SplitPrototype{
      project_id: project_id,
      prototype_id: prototype_id,
      found_page_count: found_page_count,
      role_count: role_count,
      timed_out: timed_out,
      split_by: account_id,
      split_at: DateTime.utc_now() |> DateTime.truncate(:second)
    }

    with {:ok, %{events: [%PrototypeSplitIntoPages{} = event]}} <-
           CommandedApp.dispatch(command, consistency: :strong, returning: :execution_result) do
      :ok = PrototypePage.replace!(event.prototype_id, kept_pages(pages))
      {:ok, event}
    end
  end

  @doc """
  Undoes the project's split (slice undo-split): dispatches UndoSplit, then
  removes the split's stored pages.
  """
  @spec undo_split(Ecto.UUID.t(), Ecto.UUID.t(), Ecto.UUID.t()) ::
          {:ok, SplitUndone.t()} | {:error, term()}
  def undo_split(project_id, prototype_id, account_id) do
    command = %UndoSplit{
      project_id: project_id,
      prototype_id: prototype_id,
      undone_by: account_id,
      undone_at: DateTime.utc_now() |> DateTime.truncate(:second)
    }

    with {:ok, %{events: [%SplitUndone{} = event]}} <-
           CommandedApp.dispatch(command, consistency: :strong, returning: :execution_result) do
      :ok = PrototypePage.remove!(event.prototype_id)
      {:ok, event}
    end
  end

  @doc "The board's sentence after a split of `file_name` is undone."
  def undo_note(file_name), do: "Undid the split. The tabs show #{file_name} again."

  @doc "The pages a split keeps: the first 80 in the order found."
  def kept_pages(pages), do: Enum.take(pages, Project.max_pages())

  @doc "The board's sentence after a split of `file_name`."
  def split_note(file_name, %PrototypeSplitIntoPages{} = split) do
    stopped =
      cond do
        split.skipped_count > 0 -> " (stopped at #{split.page_count})"
        split.timed_out -> " (stopped after 4 minutes)"
        true -> ""
      end

    "Split #{file_name} into #{count(split.page_count, "page")}#{roles(split.role_count)}#{stopped}. " <>
      "Each tab above is one page."
  end

  defp roles(0), do: ""
  defp roles(role_count), do: " across #{count(role_count, "role")}"

  defp count(1, noun), do: "1 #{noun}"
  defp count(n, noun), do: "#{n} #{noun}s"
end
