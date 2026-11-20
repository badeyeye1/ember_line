defmodule EmberLine.Modeling.Projections.SlicesToCreateProjection do
  @moduledoc """
  Projection SlicesToCreateProjection (slice create-derived-slices): builds
  SlicesToCreate, the automation's list, and AddedSlices, every slice the
  project has. Listing a derive's slices also starts the automation's job
  (`EmberLine.Modeling.CreateDerivedSlices`), in the same transaction.

  FeatureDerived ("list the feature's new slices with featureId set") is
  handled when derive-feature is built.

  Strongly consistent, so a command dispatched with `consistency: :strong`
  returns after the lists are updated.
  """
  use Commanded.Projections.Ecto,
    application: EmberLine.CommandedApp,
    repo: EmberLine.Repo,
    name: "SlicesToCreateProjection",
    consistency: :strong

  import Ecto.Query, only: [from: 2]

  alias EmberLine.Modeling.{CreateDerivedSlices, Derivation}
  alias EmberLine.Modeling.Project.ModelDerived
  alias EmberLine.Modeling.Projections.{AddedSlices, SlicesToCreate}
  alias EmberLine.Modeling.Slice.SliceAdded

  # "list each outline slice from the stored Derivation whose id, or whose
  # name (ignoring case) and screen, isn't in AddedSlices, with its details
  # and position"
  project(%ModelDerived{} = event, _metadata, fn multi ->
    Ecto.Multi.run(multi, :slices_to_create, fn repo, _changes ->
      rows = to_create(repo, event)

      repo.insert_all(SlicesToCreate, rows,
        on_conflict: :replace_all,
        conflict_target: [:slice_id]
      )

      if rows != [] do
        %{project_id: event.project_id, derivation_id: event.derivation_id}
        |> CreateDerivedSlices.new()
        |> Oban.insert()
      else
        {:ok, nil}
      end
    end)
  end)

  # "add the slice to AddedSlices (sliceId, name, screenId) and take it off the list"
  project(%SliceAdded{} = event, _metadata, fn multi ->
    multi
    |> Ecto.Multi.insert_all(
      :added_slices,
      AddedSlices,
      [
        %{
          slice_id: event.slice_id,
          project_id: event.project_id,
          name: event.name,
          screen_id: event.screen_id
        }
      ],
      on_conflict: :nothing,
      conflict_target: [:slice_id]
    )
    |> Ecto.Multi.delete_all(
      :slices_to_create,
      from(row in SlicesToCreate, where: row.slice_id == ^event.slice_id)
    )
  end)

  defp to_create(repo, %ModelDerived{} = event) do
    outline =
      case Derivation.get(event.derivation_id) do
        %{slices: slices} -> Map.new(slices, &{&1["id"], &1})
        nil -> %{}
      end

    added =
      repo.all(
        from(a in AddedSlices,
          where: a.project_id == ^event.project_id,
          select: {a.slice_id, a.name, a.screen_id}
        )
      )

    ids = MapSet.new(added, &elem(&1, 0))
    names = MapSet.new(added, fn {_id, name, screen} -> {String.downcase(name), screen} end)

    for id <- event.slice_ids,
        slice = outline[id],
        slice != nil,
        id not in ids,
        {String.downcase(slice["name"]), slice["screen"]} not in names do
      row(event, slice)
    end
  end

  defp row(event, slice) do
    %{
      slice_id: slice["id"],
      project_id: event.project_id,
      derivation_id: event.derivation_id,
      name: slice["name"],
      pattern: slice["pattern"],
      screen_id: slice["screen"],
      position: slice["position"],
      feature_id: nil,
      produces: strings(slice["produces"]),
      reads: strings(slice["reads"]),
      command_name: text(slice["command"]),
      read_model_name: text(slice["readModel"])
    }
  end

  defp strings(list) when is_list(list), do: for(s <- list, is_binary(s), do: s)
  defp strings(_other), do: []

  defp text(value) when is_binary(value), do: value
  defp text(_none), do: ""
end
