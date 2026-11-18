defmodule EmberLineWeb.AccountNotificationsLive do
  @moduledoc """
  Screen account-notifications: channel toggles for each kind of update
  (slice set-notif-pref). Each toggle saves straight away.

  Shows the member's saved choices; anything not saved yet shows as off.
  Labels, defaults and the Slack column's availability belong to the
  view-notif-prefs slice.
  """
  use EmberLineWeb, :live_view

  alias EmberLine.Accounts.NotificationPreference

  on_mount {EmberLineWeb.LiveUserAuth, :live_user_required}

  @kinds ~w(mention review reply comment agent digest)
  @channels [{"app", "In app"}, {"email", "Email"}, {"slack", "Slack"}]
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
    <Layouts.app flash={@flash}>
      <.header>Notifications</.header>
      <p :if={@error} class="alert alert-error" role="alert">{@error}</p>

      <table class="table">
        <thead>
          <tr>
            <th>Notify me about</th>
            <th :for={{_channel, label} <- @channels}>{label}</th>
          </tr>
        </thead>
        <tbody>
          <tr :for={kind <- @kinds} id={"kind-#{kind}"}>
            <td>{String.capitalize(kind)}</td>
            <td :for={{channel, label} <- @channels}>
              <input
                type="checkbox"
                class="toggle"
                id={"pref-#{kind}-#{channel}"}
                aria-label={"#{String.capitalize(kind)}: #{label}"}
                checked={Map.get(@choices, {kind, channel}, false)}
                phx-click="toggle"
                phx-value-kind={kind}
                phx-value-channel={channel}
              />
            </td>
          </tr>
        </tbody>
      </table>
    </Layouts.app>
    """
  end
end
