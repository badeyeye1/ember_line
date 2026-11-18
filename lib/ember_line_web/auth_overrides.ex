defmodule EmberLineWeb.AuthOverrides do
  @moduledoc """
  Styles the AshAuthentication.Phoenix pages we don't replace (confirm email,
  magic-link sign-in and sign-out) with Emberline's `ui-` classes. They render
  inside `Layouts.auth_live/1`, the auth shell.
  """
  use AshAuthentication.Phoenix.Overrides

  alias AshAuthentication.Phoenix.{Components, ConfirmLive, MagicSignInLive, SignOutLive}

  @heading "text-[26px] font-[650] tracking-[-0.02em] m-0 mb-4"
  @button "ui-btn primary wide"

  override ConfirmLive do
    set :root_class, nil
  end

  override MagicSignInLive do
    set :root_class, nil
  end

  override SignOutLive do
    set :root_class, nil
  end

  override Components.Confirm do
    set :root_class, "grid gap-4"
    set :strategy_class, nil
  end

  override Components.Confirm.Input do
    set :submit_class, @button
  end

  override Components.MagicLink do
    set :root_class, "grid gap-4"
    set :label_class, @heading
  end

  override Components.MagicLink.Input do
    set :submit_class, @button
    set :remember_me_class, "ui-chk my-3"
    set :checkbox_class, nil
    set :checkbox_label_class, nil
    set :remember_me_input_label, "Keep me signed in"
  end

  override Components.SignOut do
    set :root_class, "grid gap-4"
    set :h2_class, @heading
    set :info_text_class, "text-muted m-0"
    set :button_class, @button
  end

  override Components.Flash do
    set :message_class_info, "ui-toast fixed right-4 bottom-4 z-50"
    set :message_class_error, "ui-toast error fixed right-4 bottom-4 z-50"
  end
end
