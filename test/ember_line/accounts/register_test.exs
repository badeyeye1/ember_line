defmodule EmberLine.Accounts.RegisterTest do
  @moduledoc "Slice register: one test per scenario in docs/model.json."
  use EmberLine.DataCase, async: false

  import EmberLine.ScenarioCase

  require Ash.Query

  alias EmberLine.Accounts.User

  @event "AccountRegistered"

  defp register(fields) do
    params =
      Map.merge(
        %{
          full_name: "Ada Lovelace",
          email: "ada@company.com",
          password: "secret123",
          terms_accepted: true
        },
        Map.new(fields)
      )

    User
    |> Ash.Changeset.for_create(:register_account, params)
    |> Ash.create(authorize?: false)
  end

  defp no_account_for(email) do
    assert [] = User |> Ash.Query.filter(email == ^email) |> Ash.read!(authorize?: false)
  end

  test "Valid details create an unverified account" do
    assert {:ok, user} = register([])

    assert user.full_name == "Ada Lovelace"
    assert to_string(user.email) == "ada@company.com"
    assert is_nil(user.confirmed_at)

    [event] = assert_events(@event, user.id, 1)
    assert event.stream == "Account"

    assert %{
             "accountId" => account_id,
             "fullName" => "Ada Lovelace",
             "email" => "ada@company.com",
             "verified" => false,
             "registeredAt" => registered_at,
             "avatarColor" => avatar_color
           } = event.data

    assert account_id == user.id
    assert {:ok, at, 0} = DateTime.from_iso8601(registered_at)
    assert DateTime.compare(at, user.registered_at) == :eq
    assert avatar_color == user.avatar_color
    assert avatar_color =~ ~r/^#[0-9a-f]{6}$/
  end

  test "Name is empty" do
    for blank <- ["", "   "] do
      assert {:error, error} = register(full_name: blank)
      assert error_message?(error, "Enter your name so teammates know who's commenting.")
    end

    no_account_for("ada@company.com")
  end

  test "Email is not valid" do
    assert {:error, error} = register(email: "ada-at-company")
    assert error_message?(error, "Enter a work email, like name@company.com.")
    no_account_for("ada-at-company")
  end

  test "Email already has an account" do
    {:ok, existing} = register([])

    for email <- ["ada@company.com", "ADA@Company.com"] do
      assert {:error, error} = register(email: email)
      assert error_message?(error, "There's already an account for #{email}.")
    end

    assert_events(@event, existing.id, 1)
  end

  test "Password too weak" do
    for weak <- ["abcdefgh", "12345678", "abc123"] do
      assert {:error, error} = register(password: weak)
      assert error_message?(error, "Use at least 8 characters, with a letter and a number.")
    end

    no_account_for("ada@company.com")
  end

  test "Terms not accepted" do
    assert {:error, error} = register(terms_accepted: false)
    assert error_message?(error, "Agree to the terms to create an account.")
    no_account_for("ada@company.com")
  end

  # Not a model scenario: two sign-ups for one email at the same moment
  # create one account (the unique index decides).
  test "two registrations for one email at once create one account" do
    results =
      [fn -> register([]) end, fn -> register([]) end]
      |> Enum.map(&Task.async/1)
      |> Enum.map(&Task.await/1)

    assert [{:ok, _}] = Enum.filter(results, &match?({:ok, _}, &1))
    assert [{:error, error}] = Enum.filter(results, &match?({:error, _}, &1))
    assert error_message?(error, "There's already an account for ada@company.com.")
  end
end
