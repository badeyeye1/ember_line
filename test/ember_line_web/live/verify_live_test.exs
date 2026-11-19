defmodule EmberLineWeb.VerifyLiveTest do
  @moduledoc "Screen verify: verify-email's code form (docs/design/screens/verify.*)."
  use EmberLineWeb.ConnCase, async: false

  import EmberLine.Given.Account
  import Phoenix.LiveViewTest

  alias EmberLine.Accounts.User
  alias EmberLineWeb.VerifyLive

  defp digits(code),
    do: code |> String.graphemes() |> Enum.with_index() |> Map.new(fn {d, i} -> {"#{i}", d} end)

  test "New account verifies with a valid code", %{conn: conn} do
    {account, code} = account_registered(full_name: "Ada Lovelace")
    {:ok, view, html} = live(conn, ~p"/verify/#{VerifyLive.token_for(account)}")
    assert html =~ "Check your email"

    view |> form("#verify-form", code: digits(code)) |> render_submit()
    conn = follow_trigger_action(form(view, "#verify-session-form"), conn)

    assert "/workspaces/" <> rest = redirected_to(conn)
    assert String.ends_with?(rest, "/projects")
    assert get_session(conn, "user_token")
  end

  test "Shows the email the code was sent to", %{conn: conn} do
    {account, _code} = account_registered(email: "ada@company.com")
    {:ok, _view, html} = live(conn, ~p"/verify/#{VerifyLive.token_for(account)}")

    assert html =~ "We sent a 6-digit code to <b>ada@company.com</b>"
  end

  test "No account is waiting to verify: a verified account sees nothing to verify", %{conn: conn} do
    {account, code} = account_registered()
    {:ok, _} = User.verify_email(account.id, code, nil)
    {:ok, _view, html} = live(conn, ~p"/verify/#{VerifyLive.token_for(account)}")

    assert html =~ "Nothing to verify"
  end

  test "Resend after the wait has passed", %{conn: conn} do
    {account, _code} = account_registered()
    code_sent_seconds_ago(account, 60)
    {:ok, view, _html} = live(conn, ~p"/verify/#{VerifyLive.token_for(account)}")

    assert view |> element("button", "Resend the code") |> render_click() =~ "Sent a new code."
  end

  test "Resend too soon", %{conn: conn} do
    {account, _code} = account_registered()
    {:ok, view, _html} = live(conn, ~p"/verify/#{VerifyLive.token_for(account)}")

    assert view |> element("button", "Resend the code") |> render_click() =~
             "You can resend in 30 s."
  end

  test "Code is wrong", %{conn: conn} do
    {account, code} = account_registered()
    wrong = if code == "999999", do: "999998", else: "999999"
    {:ok, view, _html} = live(conn, ~p"/verify/#{VerifyLive.token_for(account)}")

    html = view |> form("#verify-form", code: digits(wrong)) |> render_submit()

    assert html =~ "That code isn&#39;t right. Check your email or send a new one."
  end

  test "Code has fewer than six digits", %{conn: conn} do
    {account, _code} = account_registered()
    {:ok, view, _html} = live(conn, ~p"/verify/#{VerifyLive.token_for(account)}")

    html = view |> form("#verify-form", code: digits("123")) |> render_submit()

    assert html =~ "Enter all 6 digits."
  end

  test "Account does not exist", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/verify/not-a-real-token")

    assert html =~ "Nothing to verify"
    assert html =~ "Sign in first."
    assert has_element?(view, "a", "Go to sign in")
  end
end
