defmodule EmberLine.Accounts.SignInLock do
  @moduledoc """
  The signin lock: 5 failed sign-ins for one email within a rolling 15
  minutes lock that email for 15 minutes from the fifth failure. A successful
  sign-in clears the count. Emails are compared lower-cased.
  """
  require Ash.Query

  alias EmberLine.Accounts.SignInFailureCount
  alias EmberLine.Repo

  @window_seconds 15 * 60
  @max_failures 5

  @doc "Is `email` locked at `now`?"
  def locked?(email, now) do
    case get(email) do
      %{locked_until: %DateTime{} = until} -> DateTime.compare(until, now) == :gt
      _ -> false
    end
  end

  @doc "Records a failed sign-in for `email` at `now`; the fifth in the window locks it."
  def record_failure!(email, now) do
    {:ok, _} =
      Repo.transaction(fn ->
        email = normalize(email)
        count = get(email, lock: true)
        recent = recent(count, now) ++ [now]

        attrs =
          if length(recent) >= @max_failures,
            do: %{failed_at: [], locked_until: DateTime.add(now, @window_seconds, :second)},
            else: %{failed_at: recent, locked_until: nil}

        save!(count, email, attrs)
      end)

    :ok
  end

  @doc "A successful sign-in clears `email`'s count."
  def clear!(email) do
    case get(email) do
      nil -> :ok
      count -> Ash.destroy!(count, authorize?: false)
    end
  end

  defp recent(nil, _now), do: []

  defp recent(count, now),
    do: Enum.filter(count.failed_at, &(DateTime.diff(now, &1, :second) < @window_seconds))

  defp save!(nil, email, attrs) do
    SignInFailureCount
    |> Ash.Changeset.for_create(:start, Map.put(attrs, :email, email))
    |> Ash.create!(authorize?: false)
  end

  defp save!(count, _email, attrs) do
    count |> Ash.Changeset.for_update(:set, attrs) |> Ash.update!(authorize?: false)
  end

  defp get(email, opts \\ []) do
    SignInFailureCount
    |> Ash.Query.filter(email == ^normalize(email))
    |> then(&if(opts[:lock], do: Ash.Query.lock(&1, "FOR UPDATE"), else: &1))
    |> Ash.read_one!(authorize?: false)
  end

  defp normalize(email), do: email |> to_string() |> String.trim() |> String.downcase()
end
