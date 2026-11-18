defmodule EmberLineWeb.Layouts do
  @moduledoc """
  Emberline's layouts: `app/1` (the app shell: sidebar and top bar) for
  signed-in screens, and `auth/1` (the auth shell) for sign-in, sign-up and
  password screens. Both are built from `EmberLineWeb.UI`.
  """
  use EmberLineWeb, :html

  embed_templates "layouts/*"

  @doc """
  The app shell. `crumbs` is the breadcrumb, `nav` the current sidebar item.

      <Layouts.app flash={@flash} current_user={@current_user} crumbs={[{"Notifications", nil}]}>
        ...
      </Layouts.app>
  """
  attr :flash, :map, required: true
  attr :current_user, :map, default: nil
  attr :workspace, :map, default: nil
  attr :projects, :list, default: []
  attr :project, :map, default: nil
  attr :nav, :atom, default: nil
  attr :crumbs, :list, default: []
  slot :top_right
  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <.app_shell
      current_user={@current_user}
      workspace={@workspace}
      projects={@projects}
      project={@project}
      nav={@nav}
      crumbs={@crumbs}
    >
      <:top_right>{render_slot(@top_right)}</:top_right>
      {render_slot(@inner_block)}
    </.app_shell>
    <.flash_group flash={@flash} />
    """
  end

  @doc "The auth shell: the form on the left, the purple panel on the right."
  attr :flash, :map, required: true
  slot :inner_block, required: true

  def auth(assigns) do
    ~H"""
    <.auth_shell>{render_slot(@inner_block)}</.auth_shell>
    <.flash_group flash={@flash} />
    """
  end

  @doc "Flash messages and connection notices, as toasts."
  attr :flash, :map, required: true

  def flash_group(assigns) do
    ~H"""
    <.toasts flash={@flash} />
    <div class="ui-toasts" aria-live="assertive">
      <div
        id="client-error"
        class="ui-toast error"
        phx-disconnected={JS.remove_attribute("hidden", to: ".phx-client-error #client-error")}
        phx-connected={JS.set_attribute({"hidden", ""})}
        hidden
      >
        <p>{gettext("We can't find the internet. Attempting to reconnect…")}</p>
      </div>
      <div
        id="server-error"
        class="ui-toast error"
        phx-disconnected={JS.remove_attribute("hidden", to: ".phx-server-error #server-error")}
        phx-connected={JS.set_attribute({"hidden", ""})}
        hidden
      >
        <p>{gettext("Something went wrong. Attempting to reconnect…")}</p>
      </div>
    </div>
    """
  end
end
