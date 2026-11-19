defmodule EmberLine.Accounts.VerifyEmailTest do
  @moduledoc "Slice verify-email: one test per scenario in docs/model.json."
  use EmberLine.DataCase, async: false

  import EmberLine.Given.Account
  import EmberLine.ScenarioCase

  alias EmberLine.Accounts.{User, Workspace}

  require Ash.Query

  @device "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"

  defp verify(account_id, code) do
    User.verify_email(account_id, code, @device)
  end

  defp workspaces_of(account) do
    Workspace |> Ash.Query.filter(owner_account_id == ^account.id) |> Ash.read!(authorize?: false)
  end

  defp reloaded(account), do: Ash.get!(User, account.id, authorize?: false)

  test "New account verifies with a valid code" do
    {account, code} = account_registered(full_name: "Ada Lovelace")
    code_sent_minutes_ago(account, 2)

    assert {:ok, %{status: :verified, token: token}} = verify(account.id, code)
    assert reloaded(account).confirmed_at

    [verified] = assert_events("EmailVerified", account.id, 1)
    assert %{"accountId" => id, "email" => email, "verifiedAt" => _} = verified.data
    assert id == account.id and email == to_string(account.email)

    [signed_in] = assert_events("SignedIn", account.id, 1)

    assert %{
             "accountId" => ^id,
             "method" => "verification",
             "keepSignedIn" => false,
             "sessionId" => session_id,
             "device" => "Chrome on macOS",
             "signedInAt" => _
           } = signed_in.data

    assert {:ok, %{"jti" => ^session_id}, _resource} =
             AshAuthentication.Jwt.verify(token, :ember_line)

    [workspace] = workspaces_of(account)
    assert {workspace.name, workspace.slug} == {"Ada's workspace", "adas-workspace"}
    [created] = assert_events("WorkspaceCreated", workspace.id, 1)

    assert created.data == %{
             "workspaceId" => workspace.id,
             "ownerAccountId" => account.id,
             "name" => "Ada's workspace",
             "slug" => "adas-workspace",
             "createdAt" => created.data["createdAt"]
           }
  end

  test "Existing unverified account verifies without a new workspace" do
    {account, code} = account_registered(full_name: "Sam Carter")
    existing = workspace_created(account)

    assert {:ok, %{status: :verified, workspace_id: workspace_id}} = verify(account.id, code)
    assert workspace_id == existing.id

    assert_events("EmailVerified", account.id, 1)
    [signed_in] = assert_events("SignedIn", account.id, 1)
    assert signed_in.data["method"] == "verification"
    assert [_only_the_existing_one] = workspaces_of(account)
    assert_events("WorkspaceCreated", existing.id, 0)
  end

  test "Code has fewer than six digits" do
    {account, _code} = account_registered()

    for short <- ["123", "", "12345a"] do
      assert {:error, error} = verify(account.id, short)
      assert error_message?(error, "Enter all 6 digits.")
    end

    refute reloaded(account).confirmed_at
  end

  test "Account does not exist" do
    assert {:error, error} = verify(Ecto.UUID.generate(), "123456")
    assert error_message?(error, "Nothing to verify. Sign in first.")
  end

  test "Code is wrong" do
    {account, code} = account_registered()
    wrong = if code == "999999", do: "999998", else: "999999"

    assert {:error, error} = verify(account.id, wrong)
    assert error_message?(error, "That code isn't right. Check your email or send a new one.")
    refute reloaded(account).confirmed_at
    assert reloaded(account).verification_attempts == 1
    assert_events("EmailVerified", account.id, 0)
  end

  test "Code expired" do
    {account, code} = account_registered()
    code_sent_minutes_ago(account, 16)

    assert {:error, error} = verify(account.id, code)
    assert error_message?(error, "That code has expired. Send a new one.")
    refute reloaded(account).confirmed_at
  end

  test "Too many wrong tries" do
    {account, code} = account_registered()
    wrong = if code == "999999", do: "999998", else: "999999"
    for _ <- 1..5, do: verify(account.id, wrong)

    assert {:error, error} = verify(account.id, code)
    assert error_message?(error, "Too many tries. Send a new code.")
    refute reloaded(account).confirmed_at
  end

  test "Already verified account verifies again" do
    {account, code} = account_registered()
    assert {:ok, %{status: :verified}} = verify(account.id, code)

    assert {:ok, %{status: :already_verified}} = verify(account.id, code)
    assert_events("EmailVerified", account.id, 1)
    assert_events("SignedIn", account.id, 1)
    assert [_one] = workspaces_of(account)
  end

  test "A resent code replaces the old one" do
    {account, old_code} = account_registered()
    new_code = verification_code_resent(account)
    # Two random codes can collide; then the old one *is* the new one.
    if old_code != new_code do
      assert {:error, error} = verify(account.id, old_code)
      assert error_message?(error, "That code isn't right. Check your email or send a new one.")
    end

    assert {:ok, %{status: :verified}} = verify(account.id, new_code)
  end

  test "Workspace slug already taken" do
    {first, first_code} = account_registered(full_name: "Ada Lovelace")
    {:ok, _} = verify(first.id, first_code)
    {account, code} = account_registered(full_name: "Ada Byron", email: "ada@other.com")

    assert {:ok, %{status: :verified}} = verify(account.id, code)
    assert_events("EmailVerified", account.id, 1)
    [workspace] = workspaces_of(account)
    assert {workspace.name, workspace.slug} == {"Ada's workspace", "adas-workspace-2"}
    [created] = assert_events("WorkspaceCreated", workspace.id, 1)
    assert created.data["slug"] == "adas-workspace-2"
  end

  # Not a model scenario: the code is never stored in plain text.
  test "the code is stored hashed, not in plain text" do
    {account, code} = account_registered()
    stored = reloaded(account).verification_code_hash
    assert is_binary(stored) and stored != code and not String.contains?(stored, code)
  end

  # Not a model scenario: wrong tries at the same time are all counted (the
  # account row is locked while a code is checked).
  test "wrong codes sent at once are all counted" do
    {account, code} = account_registered()
    wrong = if code == "999999", do: "999998", else: "999999"

    1..5
    |> Enum.map(fn _ -> Task.async(fn -> verify(account.id, wrong) end) end)
    |> Enum.each(&Task.await/1)

    assert reloaded(account).verification_attempts == 5
  end
end
