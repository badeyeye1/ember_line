defmodule EmberLineWeb.AccountNotificationsLive do
  @moduledoc """
  Screen account-notifications: channel toggles for each kind of update
  (slice set-notif-pref). Each toggle saves straight away.

  Shows the member's saved choices; anything not saved yet shows as off.
  Defaults and the Slack column's availability belong to the view-notif-prefs
  slice; until Slack can be connected, its column is disabled, as in the
  reference.
  """
  use EmberLineWeb, :live_view

  alias EmberLine.Accounts.NotificationPreference

  on_mount {EmberLineWeb.LiveUserAuth, :live_user_required}

  # Labels and descriptions from docs/design/screens/account-notifications.html.
  @kinds [
    {"mention", "Mentions", "Someone @mentions you"},
    {"review", "Review requests",
     "Someone asks you to review a slice's spec, or answers your request"},
    {"reply", "Replies", "Someone replies in a thread you're in"},
    {"comment", "Comments on your slices", "New comments on slices you own"},
    {"agent", "Build updates", "Your agent opens a pull request or a check fails"},
    {"digest", "Weekly digest", "A Monday summary of what changed in your projects"}
  ]
  @channels [{"app", "In-app"}, {"email", "Email"}, {"slack", "Slack"}]
  @channel_values %{"app" => :app, "email" => :email, "slack" => :slack}

  @messages %{
    "SlackNotConnected" => "Connect Slack to your workspace first.",
    "UnknownNotificationKind" => "That kind of update doesn't exist."
  }

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket |> assign(page_title: "Notifications", error: nil) |> assign_choices()}
  end

  @impl true
  def handle_event("toggle", %{"kind" => kind, "channel" => channel}, socket) do
    user = socket.assigns.current_user
    enabled = not Map.get(socket.assigns.choices, {kind, channel}, false)

    case NotificationPreference.change_notification_preference(
           kind,
           Map.get(@channel_values, channel),
           enabled,
           actor: user
         ) do
      {:ok, _preference} ->
        {:noreply, socket |> assign(error: nil) |> assign_choices()}

      {:error, error} ->
        {:noreply, assign(socket, error: message(error))}
    end
  end

  defp assign_choices(socket) do
    choices =
      NotificationPreference
      |> Ash.read!(actor: socket.assigns.current_user)
      |> Map.new(&{{Atom.to_string(&1.kind), Atom.to_string(&1.channel)}, &1.enabled})

    assign(socket, choices: choices)
  end

  defp message(%{errors: errors}) do
    Enum.find_value(errors, "Something went wrong. Try again.", fn
      %{message: message} -> Map.get(@messages, message)
      _ -> nil
    end)
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, kinds: @kinds, channels: @channels)

    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} crumbs={[{"Notifications", nil}]}>
      <section class="ui-page" aria-label="Account">
        <.page_header title="Notifications" description="Choose what reaches you, and where." />
        <div class="ui-pg">
          <.settings_nav current={:account_notifications} />
          <div class="ui-pg-main">
            <.notice :if={@error} tone="err">{@error}</.notice>
            <.card title="Notify me about">
              <:header_text>
                In-app notifications appear in your Inbox. Slack needs the Slack integration.
              </:header_text>
              <div class="mt-2">
                <div class="ui-nrow h">
                  <span></span><span :for={{_channel, label} <- @channels}>{label}</span>
                </div>
                <div :for={{kind, label, description} <- @kinds} class="ui-nrow" id={"kind-#{kind}"}>
                  <span><b>{label}</b><small>{description}</small></span>
                  <.switch
                    :for={{channel, channel_label} <- @channels}
                    id={"pref-#{kind}-#{channel}"}
                    label={"#{label}: #{channel_label}"}
                    checked={Map.get(@choices, {kind, channel}, false)}
                    disabled={channel == "slack"}
                    phx-click="toggle"
                    phx-value-kind={kind}
                    phx-value-channel={channel}
                  />
                </div>
              </div>
            </.card>
          </div>
        </div>
      </section>
    </Layouts.app>
    """
  end
end
