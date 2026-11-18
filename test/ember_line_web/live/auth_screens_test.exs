defmodule EmberLineWeb.AuthScreensTest do
  @moduledoc "The sign-in, forgot, forgot-sent and reset screens (docs/design/screens)."
  use EmberLineWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Swoosh.TestAssertions

  alias EmberLine.Accounts.User

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

  test "sign in posts to the password strategy and signs the member in", %{conn: conn} do
    account!()
    {:ok, view, html} = live(conn, ~p"/sign-in")
    assert html =~ "Welcome back. Sign in to your workspace."

    form =
      form(view, "#sign-in-form", user: %{email: "ada@company.com", password: @password})

    render_submit(form)
    conn = follow_trigger_action(form, conn)

    assert redirected_to(conn) == ~p"/"
    assert get_session(conn, "user_token")
  end

  test "a wrong password comes back to sign in with the error", %{conn: conn} do
    account!()

    conn =
      post(conn, ~p"/auth/user/password/sign_in",
        user: %{email: "ada@company.com", password: "nope1234"}
      )

    assert redirected_to(conn) == ~p"/sign-in"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Incorrect email or password"
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
