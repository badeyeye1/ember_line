defmodule EmberLine.Accounts.SetNotifPrefTest do
  @moduledoc "Slice set-notif-pref: one test per scenario in docs/model.json."
  use EmberLine.DataCase, async: false

  import EmberLine.Given.Account
  import EmberLine.ScenarioCase

  alias EmberLine.Accounts.NotificationPreference

  @event "NotificationPreferenceChanged"

  setup do
    %{account: account()}
  end

  defp change(account, kind, channel, enabled) do
    NotificationPreference.change_notification_preference(kind, channel, enabled, actor: account)
  end

  defp data(account, kind, channel, enabled) do
    %{"accountId" => account.id, "kind" => kind, "channel" => channel, "enabled" => enabled}
  end

  test "Turn email on for mentions", %{account: account} do
    assert {:ok, preference} = change(account, "mention", :email, true)

    assert {preference.account_id, preference.kind, preference.channel, preference.enabled} ==
             {account.id, :mention, :email, true}

    [event] = assert_events(@event, account.id, 1)
    assert event.stream == "Account"
    assert event.data == data(account, "mention", "email", true)
  end

  test "Turn in-app off for the weekly digest", %{account: account} do
    notification_preference_changed(account, "digest", :app, true)

    assert {:ok, %{enabled: false}} = change(account, "digest", :app, false)

    [_on, off] = assert_events(@event, account.id, 2)
    assert off.data == data(account, "digest", "app", false)
  end

  test "Slack not connected", %{account: account} do
    assert {:error, error} = change(account, "mention", :slack, true)
    assert error_message?(error, "SlackNotConnected")
    assert_events(@event, account.id, 0)
  end

  test "Unknown kind of update", %{account: account} do
    assert {:error, error} = change(account, "gossip", :app, true)
    assert error_message?(error, "UnknownNotificationKind")
    assert_events(@event, account.id, 0)
  end

  test "Setting the same value again", %{account: account} do
    notification_preference_changed(account, "reply", :email, true)

    assert {:ok, %{enabled: true}} = change(account, "reply", :email, true)
    assert_events(@event, account.id, 1)
  end

  test "Quick on then off", %{account: account} do
    assert {:ok, _} = change(account, "agent", :app, true)
    assert {:ok, _} = change(account, "agent", :app, false)

    assert [on, off] = assert_events(@event, account.id, 2)
    assert on.data == data(account, "agent", "app", true)
    assert off.data == data(account, "agent", "app", false)
  end

  # Not a model scenario: the same change sent twice at once records one event
  # (the database decides, through a conditional upsert).
  test "two identical changes at once record one event", %{account: account} do
    notification_preference_changed(account, "comment", :email, false)

    [
      fn -> change(account, "comment", :email, true) end,
      fn -> change(account, "comment", :email, true) end
    ]
    |> Enum.map(&Task.async/1)
    |> Enum.each(&assert({:ok, %{enabled: true}} = Task.await(&1)))

    assert_events(@event, account.id, 2)
  end

  # Not a model scenario: the account comes from the actor, so nobody can
  # change another member's preferences.
  test "changing preferences needs a signed-in account" do
    assert {:error, %Ash.Error.Invalid{errors: [%{relationship: :account}]}} =
             NotificationPreference.change_notification_preference("mention", :email, true)
  end
end
