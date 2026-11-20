defmodule EmberLine.Modeling.Projections.PrototypeScreensProjection do
  @moduledoc """
  Projection PrototypeScreensProjection: builds the PrototypeScreens read
  model (slice view-intake), one entry per project.

  Strongly consistent, so a command dispatched with `consistency: :strong`
  returns after the entry is updated.
  """
  use Commanded.Projections.Ecto,
    application: EmberLine.CommandedApp,
    repo: EmberLine.Repo,
    name: "PrototypeScreensProjection",
    consistency: :strong

  alias EmberLine.Modeling.{Intake, Prototypes}
  alias EmberLine.Modeling.Project.{PrototypeLoaded, PrototypeSplitIntoPages, SplitUndone}
  alias EmberLine.Modeling.Projections.PrototypeScreens

  # "replace the entry: tabs = one per file, fileCount, skippedCount,
  # ignoredFileNames, interactive; isSplit = false; notes worked out from these"
  project(%PrototypeLoaded{} = event, _metadata, fn multi ->
    tabs =
      event.file_names
      |> Enum.with_index(1)
      |> Enum.map(fn {name, position} ->
        PrototypeScreens.file_tab(name, position, event.interactive == true)
      end)

    entry = %{
      project_id: event.project_id,
      prototype_id: event.prototype_id,
      tabs: tabs,
      file_count: event.file_count,
      skipped_count: event.skipped_count,
      ignored_file_names: event.ignored_file_names,
      interactive: event.interactive == true,
      is_split: false,
      page_count: 0,
      skipped_page_count: 0,
      timed_out: false,
      role_count: 0
    }

    entry = Map.put(entry, :notes, load_notes(entry))

    Ecto.Multi.insert_all(multi, :prototype_screens, PrototypeScreens, [entry],
      on_conflict: {:replace_all_except, [:project_id]},
      conflict_target: [:project_id]
    )
  end)

  # "isSplit = true; pageCount, roleCount, skippedPageCount, timedOut;
  # notes = the split sentence" (the tabs are the stored pages, read with the entry)
  project(%PrototypeSplitIntoPages{} = event, _metadata, fn multi ->
    change_entry(multi, event.project_id, fn screens ->
      [first | _] = screens.tabs

      %{
        is_split: true,
        page_count: event.page_count,
        role_count: event.role_count,
        skipped_page_count: event.skipped_count,
        timed_out: event.timed_out == true,
        notes: [Prototypes.split_note(first["label"], event)]
      }
    end)
  end)

  # "isSplit = false; tabs back to the loaded files; the split note is dropped"
  project(%SplitUndone{} = event, _metadata, fn multi ->
    change_entry(multi, event.project_id, fn screens ->
      %{
        is_split: false,
        page_count: 0,
        role_count: 0,
        skipped_page_count: 0,
        timed_out: false,
        notes: load_notes(screens)
      }
    end)
  end)

  defp change_entry(multi, project_id, changes) do
    Ecto.Multi.run(multi, :prototype_screens, fn repo, _changes ->
      case repo.get(PrototypeScreens, project_id) do
        nil ->
          {:ok, nil}

        screens ->
          screens
          |> Ecto.Changeset.change(changes.(screens))
          |> repo.update()
      end
    end)
  end

  defp load_notes(entry) do
    Enum.reject(
      [
        Intake.skipped_note(entry.file_count, entry.skipped_count),
        Intake.ignored_note(entry.ignored_file_names)
      ],
      &is_nil/1
    )
  end
end
