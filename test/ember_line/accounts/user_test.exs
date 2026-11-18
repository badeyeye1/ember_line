defmodule EmberLine.Accounts.UserTest do
  use EmberLine.DataCase, async: true

  import Swoosh.TestAssertions

  alias AshAuthentication.Strategy.Password
  alias EmberLine.Accounts.User

  @password "correct horse battery staple 1"

  defp register(email) do
    User
    |> Ash.Changeset.for_create(:register_account, %{
      full_name: "Ada Lovelace",
      email: email,
      password: @password,
      terms_accepted: true
    })
    |> Ash.create(authorize?: false)
  end

  describe "password strategy" do
    test "registers a user and signs them in with the right password" do
      assert {:ok, user} = register("ada@example.com")
      assert to_string(user.email) == "ada@example.com"

      assert {:ok, [signed_in]} =
               User
               |> Ash.Query.for_read(:sign_in_with_password, %{
                 email: "ada@example.com",
                 password: @password
               })
               |> Ash.read(authorize?: false)

      assert signed_in.id == user.id
      assert signed_in.__metadata__.token
    end

    test "rejects the wrong password" do
      {:ok, _user} = register("grace@example.com")

      assert {:error, %Ash.Error.Forbidden{}} =
               User
               |> Ash.Query.for_read(:sign_in_with_password, %{
                 email: "grace@example.com",
                 password: "not the password"
               })
               |> Ash.read(authorize?: false)
    end
  end

  describe "password reset" do
    test "resets the password with a token, without a confirmation field" do
      {:ok, user} = register("grace@example.com")
      {:ok, strategy} = AshAuthentication.Info.strategy(User, :password)
      {:ok, token} = Password.reset_token_for(strategy, user)

      assert {:ok, _user} =
               user
               |> Ash.Changeset.for_update(:reset_password_with_token, %{
                 reset_token: token,
                 password: "a new password 2"
               })
               |> Ash.update(authorize?: false)

      assert {:ok, [_signed_in]} =
               User
               |> Ash.Query.for_read(:sign_in_with_password, %{
                 email: "grace@example.com",
                 password: "a new password 2"
               })
               |> Ash.read(authorize?: false)
    end
  end

  describe "magic link strategy" do
    test "requesting a magic link emails a sign-in link" do
      assert :ok =
               User
               |> Ash.ActionInput.for_action(:request_magic_link, %{email: "linus@example.com"})
               |> Ash.run_action(authorize?: false)

      assert_email_sent(fn email ->
        assert email.to == [{"", "linus@example.com"}]
        assert email.subject == "Your login link"
        assert email.html_body =~ "/magic_link/"
      end)
    end
  end
end
