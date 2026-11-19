defmodule EmberLineWeb.AuthScreensTest do
  @moduledoc "The sign-in, forgot, forgot-sent and reset screens (docs/design/screens)."
  use EmberLineWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Swoosh.TestAssertions

  alias EmberLine.Accounts.User
  alias EmberLine.Given

  @password "secret123"

  # A confirmed account with a password, seeded so no confirmation email is sent.
  defp account! do
    Ash.Seed.seed!(User, %{
      full_name: "Ada Lovelace",
      email: "ada@company.com",
      hashed_password: Bcrypt.hash_pwd_salt(@password),
      confirmed_at: DateTime.utc_now()
    })
  end

  test "Correct email and password: signs in and keeps the member signed in", %{conn: conn} do
    account!()
    {:ok, view, html} = live(conn, ~p"/sign-in")
    assert html =~ "Welcome back. Sign in to your workspace."

    view
    |> form("#sign-in-form",
      user: %{email: "ada@company.com", password: @password, keep_signed_in: "true"}
    )
    |> render_submit()

    conn = follow_trigger_action(form(view, "#sign-in-session-form"), conn)

    assert redirected_to(conn) == ~p"/"
    assert get_session(conn, "user_token")
    assert Enum.any?(Map.keys(conn.resp_cookies), &String.contains?(&1, "remember_me"))
  end

  test "Wrong password", %{conn: conn} do
    account!()
    {:ok, view, _html} = live(conn, ~p"/sign-in")

    html =
      view
      |> form("#sign-in-form", user: %{email: "ada@company.com", password: "nope12345"})
      |> render_submit()

    assert html =~ "That email and password don&#39;t match. Try again or reset your password."
    refute has_element?(view, "#sign-in-session-form")
  end

  test "Account not yet verified is sent to verification instead of signed in", %{conn: conn} do
    {_account, _code} =
      Given.Account.account_registered(
        email: "grace@company.com",
        password: "secret123"
      )

    {:ok, view, _html} = live(conn, ~p"/sign-in")

    result =
      view
      |> form("#sign-in-form", user: %{email: "grace@company.com", password: "secret123"})
      |> render_submit()

    assert {:error, {:live_redirect, %{to: "/verify/" <> _token}}} = result
    {:ok, _verify, html} = follow_redirect(result, conn)
    assert html =~ "Email not verified. Enter the 6-digit code to continue."
    assert html =~ "Check your email"
  end

  test "AshAuthentication's own password sign-in endpoint is off", %{conn: conn} do
    account!()

    conn =
      post(conn, "/auth/user/password/sign_in",
        user: %{email: "ada@company.com", password: @password}
      )

    assert conn.status == 404
    refute get_session(conn, "user_token")
  end

  test "forgot sends a reset link and shows the sent screen", %{conn: conn} do
    account!()
    {:ok, view, _html} = live(conn, ~p"/reset")

    assert {:error, {:live_redirect, %{to: "/reset/sent"}}} =
             view |> form("#forgot-form", user: %{email: "ada@company.com"}) |> render_submit()

    assert_email_sent(fn email -> email.subject =~ "eset" end)

    {:ok, _view, html} = live(conn, ~p"/reset/sent")
    assert html =~ "Check your email"
  end

  test "forgot looks the same for an unknown email", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/reset")

    assert {:error, {:live_redirect, %{to: "/reset/sent"}}} =
             view |> form("#forgot-form", user: %{email: "nobody@company.com"}) |> render_submit()

    assert_no_email_sent()
  end

  test "reset says when the passwords don't match", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/password-reset/some-token")

    html =
      view
      |> form("#reset-form", user: %{password: "newpass99", password_confirmation: "newpass98"})
      |> render_submit()

    assert html =~ "The passwords don&#39;t match."
  end
end
