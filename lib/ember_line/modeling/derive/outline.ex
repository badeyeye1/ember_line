defmodule EmberLine.Modeling.Derive.Outline do
  @moduledoc """
  Claude's outline for derive-model: reading the answer, and giving its
  slices uuids. A slice that matches an earlier one keeps that slice's id:
  two slices are the same when they have the same id, or else the same name
  (ignoring case) on the same screen. Earlier slices missing from the new
  outline are listed, never deleted.
  """

  @doc """
  Reads Claude's answer: one JSON object (code fences or text around it are
  tolerated) with at least one slice, each with a name and a pattern.
  """
  @spec parse(String.t()) :: {:ok, map()} | {:error, :answer_unreadable}
  def parse(text) do
    with {:ok, %{"slices" => [_ | _] = slices} = outline} <- decode(text),
         true <- Enum.all?(slices, &slice?/1) do
      {:ok, outline}
    else
      _unreadable -> {:error, :answer_unreadable}
    end
  end

  defp slice?(%{"name" => name, "pattern" => pattern}) when is_binary(name) and name != "",
    do: pattern in ["state_change", "state_view", "automation"]

  defp slice?(_not_a_slice), do: false

  defp decode(text) do
    trimmed =
      text
      |> String.trim()
      |> String.replace(~r/\A```(?:json)?\s*/i, "")
      |> String.replace(~r/\s*```\s*\z/, "")

    with {:error, _} <- Jason.decode(trimmed),
         [_, json] <- Regex.run(~r/(\{.*\})/s, trimmed) do
      Jason.decode(json)
    end
  end

  @doc """
  The outline to store, with uuid slice ids (earlier ones kept) and outcome
  slice lists pointing at them; and the earlier slice ids not in it.
  """
  @spec with_ids(map(), [map()]) :: {map(), [Ecto.UUID.t()]}
  def with_ids(outline, earlier_slices) do
    {slices, {ids, _used}} =
      outline["slices"]
      |> Enum.with_index(1)
      |> Enum.map_reduce({%{}, MapSet.new()}, fn {slice, position}, {ids, used} ->
        id = earlier_id(slice, earlier_slices, used) || Ecto.UUID.generate()
        ids = Map.put_new(ids, to_string(slice["id"]), id)
        {Map.merge(slice, %{"id" => id, "position" => position}), {ids, MapSet.put(used, id)}}
      end)

    outcomes =
      for outcome <- List.wrap(outline["outcomes"]), is_map(outcome) do
        Map.update(outcome, "slices", [], fn refs ->
          refs |> List.wrap() |> Enum.map(&Map.get(ids, to_string(&1))) |> Enum.reject(&is_nil/1)
        end)
      end

    new_ids = MapSet.new(slices, & &1["id"])
    not_in_new = for s <- earlier_slices, s["id"] not in new_ids, do: s["id"]

    {%{
       app: map_or_empty(outline["app"]),
       screens: list_of_maps(outline["screens"]),
       streams: map_or_empty(outline["streams"]),
       outcomes: outcomes,
       slices: slices
     }, not_in_new}
  end

  defp earlier_id(slice, earlier, used) do
    by_id = Enum.find(earlier, &(&1["id"] == slice["id"]))

    by_name =
      Enum.find(earlier, fn e ->
        e["id"] not in used and e["screen"] == slice["screen"] and
          String.downcase(to_string(e["name"])) == String.downcase(slice["name"])
      end)

    case by_id || by_name do
      %{"id" => id} -> if id in used, do: nil, else: id
      nil -> nil
    end
  end

  defp map_or_empty(%{} = map), do: map
  defp map_or_empty(_other), do: %{}

  defp list_of_maps(list) when is_list(list), do: Enum.filter(list, &is_map/1)
  defp list_of_maps(_other), do: []
end
