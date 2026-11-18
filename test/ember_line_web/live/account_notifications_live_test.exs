defmodule EmberLineWeb.AccountNotificationsLiveTest do
  @moduledoc "Screen account-notifications: set-notif-pref's channel toggles."
  use EmberLineWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias AshAuthentication.Plug.Helpers, as: AuthHelpers
  alias EmberLine.Accounts.NotificationPreference
  alias EmberLine.Given

  setup %{conn: conn} do
    user = Given.Account.account()
    conn = conn |> init_test_session(%{}) |> AuthHelpers.store_in_session(user)
    %{conn: conn, user: user}
  end

  test "signed-out visitors are sent to sign in" do
    assert {:error, {:redirect, %{to: "/sign-in"}}} =
             live(build_conn(), ~p"/account/notifications")
  end

  test "Turn email on for mentions", %{conn: conn, user: user} do
    {:ok, view, _html} = live(conn, ~p"/account/notifications")
    refute has_element?(view, "#pref-mention-email[checked]")

    view |> element("#pref-mention-email") |> render_click()

    assert has_element?(view, "#pref-mention-email[checked]")

    assert [%{kind: :mention, channel: :email, enabled: true}] =
             Ash.read!(NotificationPreference, actor: user)
  end

  test "Turn in-app off for the weekly digest", %{conn: conn, user: user} do
    NotificationPreference.change_notification_preference!("digest", :app, true, actor: user)
    {:ok, view, _html} = live(conn, ~p"/account/notifications")
    assert has_element?(view, "#pref-digest-app[checked]")

    view |> element("#pref-digest-app") |> render_click()

    refute has_element?(view, "#pref-digest-app[checked]")
  end

  test "Slack not connected", %{conn: conn, user: user} do
    {:ok, view, _html} = live(conn, ~p"/account/notifications")

    # Slack can't be connected yet, so its column is disabled (as in the
    # reference); the rule itself is tested in set_notif_pref_test.exs.
    for kind <- ~w(mention review reply comment agent digest) do
      assert has_element?(view, "#pref-#{kind}-slack[disabled]")
    end

    assert render(view) =~ "Slack needs the Slack integration."
    assert Ash.read!(NotificationPreference, actor: user) == []
  end
end
