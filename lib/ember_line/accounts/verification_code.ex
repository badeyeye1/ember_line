defmodule EmberLine.Accounts.VerificationCode do
  @moduledoc """
  The 6-digit code that verifies an account's email (slice verify-email).

  A code is random, emailed once, and stored only as a hash. Issuing a new one
  (at registration, or a resend) replaces the old one and resets the tries.
  """
  import Swoosh.Email

  alias EmberLine.Accounts.User
  alias EmberLine.Mailer

  @lifetime_minutes 15
  @max_attempts 5
  @resend_wait_seconds 30

  def lifetime_minutes, do: @lifetime_minutes
  def max_attempts, do: @max_attempts

  @doc "Whole seconds until a new code may be sent (0 when it may be sent now)."
  def resend_wait(%{verification_code_sent_at: nil}, _now), do: 0

  def resend_wait(%{verification_code_sent_at: sent_at}, now) do
    left_ms = @resend_wait_seconds * 1000 - DateTime.diff(now, sent_at, :millisecond)
    if left_ms > 0, do: div(left_ms + 999, 1000), else: 0
  end

  @doc "A random 6-digit code, zero-padded."
  def generate do
    <<n::unsigned-integer-size(32)>> = :crypto.strong_rand_bytes(4)
    n |> rem(1_000_000) |> Integer.to_string() |> String.pad_leading(6, "0")
  end

  def hash(code), do: Bcrypt.hash_pwd_salt(code)

  @doc "Does `code` match the stored hash? Constant time; false without a hash."
  def matches?(nil, _code), do: Bcrypt.no_user_verify()
  def matches?(hash, code), do: Bcrypt.verify_pass(code, hash)

  def expired?(%{verification_code_sent_at: nil}, _now), do: true

  def expired?(%{verification_code_sent_at: sent_at}, now),
    do: DateTime.diff(now, sent_at, :second) > @lifetime_minutes * 60

  def too_many_tries?(%{verification_attempts: attempts}), do: attempts >= @max_attempts

  @doc "Issues a new code to `account` at `now`: stores its hash, then emails it."
  def issue!(%User{} = account, now \\ DateTime.utc_now()) do
    code = generate()

    account
    |> Ash.Changeset.for_update(:set_verification_code, %{
      verification_code_hash: hash(code),
      verification_code_sent_at: now,
      verification_attempts: 0
    })
    |> Ash.update!(authorize?: false)

    send_email!(account, code)
    :ok
  end

  defp send_email!(account, code) do
    new()
    |> from(Mailer.from())
    |> to(to_string(account.email))
    |> subject("Your Emberline code: #{code}")
    |> text_body("""
    Your Emberline code is #{code}.

    Enter it on the "Check your email" page to confirm your address. It works for #{@lifetime_minutes} minutes.
    """)
    |> html_body("""
    <p>Your Emberline code is <strong style="font-size:20px;letter-spacing:4px">#{code}</strong>.</p>
    <p>Enter it on the "Check your email" page to confirm your address. It works for #{@lifetime_minutes} minutes.</p>
    """)
    |> Mailer.deliver!()
  end
end
