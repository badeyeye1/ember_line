defmodule EmberLine.Given.Account do
  @moduledoc "Given-helpers for the Account stream: reach prior state through its actions."

  import ExUnit.Assertions

  alias EmberLine.Accounts.{NotificationPreference, User, VerificationCode, Workspace}

  @doc """
  An account to act as, with a sign-in token. Seeded directly, not
  registered, so other slices' tests don't depend on the registration rules.
  """
  def account do
    user =
      Ash.Seed.seed!(User, %{email: "member-#{System.unique_integer([:positive])}@example.com"})

    {:ok, token, _claims} = AshAuthentication.Jwt.token_for_user(user)
    Ash.Resource.put_metadata(user, :token, token)
  end

  # Given NotificationPreferenceChanged(accountId, kind, channel, enabled)
  def notification_preference_changed(account, kind, channel, enabled) do
    NotificationPreference.change_notification_preference!(kind, channel, enabled, actor: account)
  end

  @doc """
  Given AccountRegistered(...): registers through the real action and returns
  `{account, code}`, the code read from the email the registration sent.
  """
  def account_registered(attrs \\ %{}) do
    params =
      Map.merge(
        %{
          full_name: "Ada Lovelace",
          email: "ada-#{System.unique_integer([:positive])}@company.com",
          password: "secret123",
          terms_accepted: true
        },
        Map.new(attrs)
      )

    account =
      User
      |> Ash.Changeset.for_create(:register_account, params)
      |> Ash.create!(authorize?: false)

    {account, code_sent_to(account)}
  end

  @doc "Given VerificationCodeResent(...): a new code replaces the old one."
  def verification_code_resent(account) do
    VerificationCode.issue!(account)
    code_sent_to(account)
  end

  @doc "Given \"code sent N minutes ago\": moves the code's sent time back."
  def code_sent_minutes_ago(account, minutes) do
    sent_at = DateTime.add(DateTime.utc_now(), -minutes * 60, :second)
    Ash.Seed.update!(account, %{verification_code_sent_at: sent_at})
  end

  @doc "Given WorkspaceCreated(ownerAccountId, ...)."
  def workspace_created(owner, attrs \\ %{}) do
    Ash.Seed.seed!(
      Workspace,
      Map.merge(
        %{
          name: "#{owner.full_name || "My"}'s workspace",
          slug: "ws-#{System.unique_integer([:positive])}",
          owner_account_id: owner.id,
          created_at: DateTime.utc_now()
        },
        Map.new(attrs)
      )
    )
  end

  # The latest email to `account`'s address in the test mailbox, and its code.
  defp code_sent_to(account) do
    to = to_string(account.email)
    assert_received {:email, %{to: [{_, ^to}], text_body: body}}
    [code] = Regex.run(~r/\b(\d{6})\b/, body, capture: :all_but_first)
    code
  end
end
