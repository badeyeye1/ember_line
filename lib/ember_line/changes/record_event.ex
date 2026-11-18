defmodule EmberLine.Changes.RecordEvent do
  @moduledoc """
  Writes the model's event to the outbox after the action's write, in the same
  transaction. If the action rolls back, so does the event.

  Options:
    * `:type` - the model's event name
    * `:stream` - the model's stream name
    * `:stream_id` - the record field holding the stream's identity
    * `:fields` - `[{"modelFieldName", :record_field | (record -> value)}]`,
      the event's fields
  """
  use Ash.Resource.Change

  alias EmberLine.Events.DomainEvent

  @impl true
  def change(changeset, opts, _context) do
    Ash.Changeset.after_action(changeset, fn _changeset, record ->
      # A skipped conditional upsert changed nothing, so there is no event.
      unless record.__metadata__[:upsert_skipped] do
        DomainEvent
        |> Ash.Changeset.for_create(:record, %{
          type: opts[:type],
          stream: opts[:stream],
          stream_id: Map.fetch!(record, opts[:stream_id]),
          data: Map.new(opts[:fields], fn {key, field} -> {key, dump(value(record, field))} end),
          occurred_at: DateTime.utc_now()
        })
        |> Ash.create!(authorize?: false)
      end

      {:ok, record}
    end)
  end

  defp value(record, field) when is_function(field, 1), do: field.(record)
  defp value(record, field), do: Map.fetch!(record, field)

  defp dump(value) when is_boolean(value) or is_nil(value), do: value
  defp dump(%Ash.CiString{} = value), do: to_string(value)
  defp dump(value) when is_atom(value), do: Atom.to_string(value)
  defp dump(value), do: value
end
