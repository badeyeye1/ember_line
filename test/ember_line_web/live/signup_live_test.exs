defmodule EmberLineWeb.SignupLiveTest do
  @moduledoc "Screen signup: register's Create account form."
  use EmberLineWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias EmberLine.Accounts.User

  @valid %{
    full_name: "Ada Lovelace",
    email: "ada@company.com",
    password: "secret123",
    terms_accepted: "true"
  }

  test "Valid details create an unverified account", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/register")

    form = form(view, "#register-form", user: @valid)
    render_submit(form)
    conn = follow_trigger_action(form, conn)

    assert redirected_to(conn) == ~p"/"
    assert [user] = Ash.read!(User, authorize?: false)
    assert user.full_name == "Ada Lovelace"
    assert is_nil(user.confirmed_at)
  end

  test "Name is empty", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/register")

    html = view |> form("#register-form", user: %{@valid | full_name: ""}) |> render_submit()

    assert html =~ "Enter your name so teammates know who&#39;s commenting."
    assert Ash.read!(User, authorize?: false) == []
  end

  test "Email already has an account", %{conn: conn} do
    Ash.Seed.seed!(User, %{email: "ada@company.com"})
    {:ok, view, _html} = live(conn, ~p"/register")

    html = view |> form("#register-form", user: @valid) |> render_submit()

    assert html =~ "There&#39;s already an account for ada@company.com."
  end

  test "Terms not accepted", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/register")

    html =
      view |> form("#register-form", user: %{@valid | terms_accepted: "false"}) |> render_submit()

    assert html =~ "Agree to the terms to create an account."
  end
end
