defmodule EmberLine.Accounts.Actions.VerifyEmail do
  @moduledoc """
  Command VerifyEmail (slice verify-email).

  Checks, in order: six digits; the account exists; not already verified
  (then nothing new happens); not too many tries; not expired; the code
  matches. A wrong code counts as a try, and that count is kept.

  On success, in one transaction: the email is confirmed, a first workspace
  is created if the account owns none, a session is started, and
  EmailVerified, SignedIn and WorkspaceCreated go to the outbox.
  """
  use Ash.Resource.Actions.Implementation

  require Ash.Query

  alias Ash.Error.Changes.InvalidArgument
  alias EmberLine.Accounts.{Device, User, VerificationCode, Workspace, WorkspaceName}
  alias EmberLine.Events
  alias EmberLine.Repo

  @messages %{
    digits: "Enter all 6 digits.",
    no_account: "Nothing to verify. Sign in first.",
    too_many: "Too many tries. Send a new code.",
    expired: "That code has expired. Send a new one.",
    wrong: "That code isn't right. Check your email or send a new one."
  }

  @impl true
  def run(input, _opts, _context) do
    code = input.arguments |> Map.get(:code) |> to_string() |> String.trim()

    if Regex.match?(~r/^\d{6}$/, code) do
      input.arguments.account_id
      |> verify(code, Device.describe(input.arguments[:device]))
      |> respond()
    else
      reject(:digits)
    end
  end

  defp verify(account_id, code, device) do
    {:ok, result} =
      Repo.transaction(fn ->
        case lock(account_id) do
          nil -> {:rejected, :no_account}
          account -> check(account, code, device, DateTime.utc_now())
        end
      end)

    result
  end

  defp check(account, code, device, now) do
    cond do
      account.confirmed_at ->
        {:ok, %{status: :already_verified, account_id: account.id}}

      VerificationCode.too_many_tries?(account) ->
        {:rejected, :too_many}

      VerificationCode.expired?(account, now) ->
        {:rejected, :expired}

      VerificationCode.matches?(account.verification_code_hash, code) ->
        verified(account, device, now)

      true ->
        wrong_try(account)
    end
  end

  # The try is saved, and the transaction still commits.
  defp wrong_try(account) do
    account
    |> Ash.Changeset.for_update(:set_verification_code, %{
      verification_attempts: account.verification_attempts + 1
    })
    |> Ash.update!(authorize?: false)

    {:rejected, :wrong}
  end

  defp verified(account, device, now) do
    account =
      account
      |> Ash.Changeset.for_update(:set_verification_code, %{
        verification_code_hash: nil,
        verification_attempts: 0
      })
      |> Ash.Changeset.force_change_attribute(:confirmed_at, now)
      |> Ash.update!(authorize?: false)

    email = to_string(account.email)

    Events.record!("EmailVerified", "Account", account.id, %{
      "accountId" => account.id,
      "email" => email,
      "verifiedAt" => now
    })

    workspace = owned_workspace(account) || create_workspace!(account, now)

    {:ok, token, claims} = AshAuthentication.Jwt.token_for_user(account)

    Events.record!("SignedIn", "Account", account.id, %{
      "accountId" => account.id,
      "signedInAt" => now,
      "method" => "verification",
      "keepSignedIn" => false,
      "sessionId" => claims["jti"],
      "device" => device
    })

    {:ok, %{status: :verified, account_id: account.id, workspace_id: workspace.id, token: token}}
  end

  defp owned_workspace(account) do
    Workspace
    |> Ash.Query.filter(owner_account_id == ^account.id)
    |> Ash.Query.sort(created_at: :asc)
    |> Ash.Query.limit(1)
    |> Ash.read_one!(authorize?: false)
  end

  defp create_workspace!(account, now) do
    name = WorkspaceName.for(account)
    base = WorkspaceName.slug(name)

    slug = WorkspaceName.free_slug!(base)

    workspace =
      Workspace
      |> Ash.Changeset.for_create(:create_for_owner, %{
        name: name,
        slug: slug,
        owner_account_id: account.id,
        created_at: now
      })
      |> Ash.create!(authorize?: false)

    Events.record!("WorkspaceCreated", "Workspace", workspace.id, %{
      "workspaceId" => workspace.id,
      "ownerAccountId" => account.id,
      "name" => name,
      "createdAt" => now,
      "slug" => slug
    })

    workspace
  end

  defp lock(account_id) do
    User
    |> Ash.Query.filter(id == ^account_id)
    |> Ash.Query.lock("FOR UPDATE")
    |> Ash.read_one!(authorize?: false)
  end

  defp respond({:ok, result}), do: {:ok, result}
  defp respond({:rejected, reason}), do: reject(reason)

  defp reject(reason) do
    {:error, InvalidArgument.exception(field: :code, message: Map.fetch!(@messages, reason))}
  end
end
