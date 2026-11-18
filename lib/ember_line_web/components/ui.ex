defmodule EmberLineWeb.UI do
  @moduledoc """
  Emberline's shared UI components, built from `docs/design/screens/*.html` and
  `docs/design/prototype.css`. Styles live in `assets/css/ui.css` (`ui-` classes)
  and colours only come from the tokens in `assets/css/app.css`.

  Every screen is built from these. Add a component here rather than styling
  one screen by hand.
  """
  use Phoenix.Component
  use Gettext, backend: EmberLineWeb.Gettext

  alias Phoenix.HTML.Form
  alias Phoenix.LiveView.JS

  # ---------------------------------------------------------------- brand

  @doc "The Emberline mark: a command, an event and a read model."
  attr :width, :integer, default: 26

  def brand_mark(assigns) do
    ~H"""
    <svg width={@width} height={round(@width * 16 / 30)} viewBox="0 0 30 16" aria-hidden="true">
      <rect x="1" y="3" width="10" height="10" rx="2.5" fill="var(--cmd-edge)" />
      <rect x="10" y="3" width="10" height="10" rx="2.5" fill="var(--evt-edge)" opacity=".95" />
      <rect x="19" y="3" width="10" height="10" rx="2.5" fill="var(--rm-edge)" opacity=".95" />
    </svg>
    """
  end

  # ---------------------------------------------------------------- app shell

  @doc """
  The app shell: sidebar (brand, workspace switcher, project picker, nav,
  account footer) and the top bar with its breadcrumb.

  `workspace` and `project` are optional maps (`%{id, name}`, plus `plan` for
  the workspace); parts of the sidebar that need them are left out until
  they're given. `nav` marks the current nav item.
  """
  attr :current_user, :map, default: nil
  attr :workspace, :map, default: nil
  attr :projects, :list, default: []
  attr :project, :map, default: nil
  attr :nav, :atom, default: nil

  attr :crumbs, :list,
    default: [],
    doc: "list of {label, href | nil}; the last is the current page"

  slot :top_right
  slot :inner_block, required: true

  def app_shell(assigns) do
    ~H"""
    <aside class="ui-side" aria-label="Navigation">
      <a href="/" class="ui-side-brand"><.brand_mark /><span>Emberline</span></a>

      <button
        :if={@workspace && @workspace[:name]}
        type="button"
        class="ui-ws-switch"
        aria-haspopup="menu"
      >
        <span class="ui-ws-logo">{initial(@workspace.name)}</span>
        <span><b>{@workspace.name}</b><small :if={@workspace[:plan]}>{@workspace.plan}</small></span>
        <svg
          viewBox="0 0 24 24"
          width="14"
          height="14"
          fill="none"
          stroke="currentColor"
          stroke-width="2"
          stroke-linecap="round"
          stroke-linejoin="round"
          aria-hidden="true"
        ><path d="M7 10l5-5 5 5M7 14l5 5 5-5"></path></svg>
      </button>

      <label :if={@projects != []} class="ui-side-label">
        Project
        <select aria-label="Switch project">
          <option
            :for={project <- @projects}
            value={project.id}
            selected={@project && project.id == @project.id}
          >
            {project.name}
          </option>
        </select>
      </label>

      <nav :if={@project} class="ui-nav" aria-label="Sections">
        <.nav_item icon={:board} label="Board" current={@nav == :board} />
        <.nav_item icon={:build} label="Build" current={@nav == :build} />
        <.nav_item icon={:sliders} label="Project settings" current={@nav == :project_settings} />
      </nav>

      <div :if={@project} class="ui-side-sep"></div>

      <nav class="ui-nav" aria-label="Workspace">
        <.nav_item
          :if={@workspace}
          icon={:folder}
          label="All projects"
          href={"/workspaces/#{@workspace.id}/projects"}
          current={@nav == :projects}
        />
        <.nav_item icon={:inbox} label="Inbox" current={@nav == :inbox} />
        <.nav_item icon={:members} label="Members" current={@nav == :members} />
        <.nav_item icon={:settings} label="Workspace settings" current={@nav == :workspace_settings} />
      </nav>

      <div class="ui-side-sep"></div>

      <a :if={@current_user} href="/account/notifications" class="ui-me-chip">
        <.avatar name={display_name(@current_user)} color={@current_user.avatar_color} />
        <span>
          <b>{display_name(@current_user)}</b>
          <small>{@current_user.email}</small>
        </span>
      </a>
      <p :if={@current_user} class="ui-side-foot"><a href="/sign-out">Sign out</a></p>
    </aside>

    <div class="ui-wrap">
      <header class="ui-top">
        <div class="ui-crumbs">
          <%= for {{label, href}, i} <- Enum.with_index(@crumbs) do %>
            <%= if i == length(@crumbs) - 1 do %>
              <b>{label}</b>
            <% else %>
              <a :if={href} href={href}>{label}</a>
              <span :if={!href}>{label}</span>
              <span class="sep">/</span>
            <% end %>
          <% end %>
        </div>
        <div class="ui-top-right">{render_slot(@top_right)}</div>
      </header>
      {render_slot(@inner_block)}
    </div>
    """
  end

  attr :icon, :atom, required: true
  attr :label, :string, required: true
  attr :href, :string, default: nil
  attr :current, :boolean, default: false
  attr :count, :integer, default: nil

  defp nav_item(assigns) do
    ~H"""
    <a
      :if={@href}
      href={@href}
      class="ui-nav-item"
      aria-current={@current && "page"}
    >
      <.nav_icon name={@icon} /><span>{@label}</span><span :if={@count} class="ui-nb">{@count}</span>
    </a>
    <span
      :if={!@href}
      class="ui-nav-item"
      aria-disabled="true"
      aria-current={@current && "page"}
      title="Not built yet"
    >
      <.nav_icon name={@icon} /><span>{@label}</span>
    </span>
    """
  end

  attr :name, :atom, required: true

  defp nav_icon(assigns) do
    ~H"""
    <svg
      viewBox="0 0 24 24"
      width="16"
      height="16"
      fill="none"
      stroke="currentColor"
      stroke-width="1.8"
      stroke-linecap="round"
      stroke-linejoin="round"
      aria-hidden="true"
    ><.nav_icon_paths name={@name} /></svg>
    """
  end

  defp nav_icon_paths(%{name: :board} = assigns) do
    ~H"""
    <rect x="3" y="4" width="18" height="16" rx="2" /><path d="M9 4v16M15 4v16" />
    """
  end

  defp nav_icon_paths(%{name: :build} = assigns) do
    ~H"""
    <circle cx="6" cy="6" r="2.2" /><circle cx="6" cy="18" r="2.2" /><circle cx="18" cy="18" r="2.2" /><path d="M6 8.2v7.6M18 15.8V10a3 3 0 0 0-3-3h-4" /><path d="M13 5l-2 2 2 2" />
    """
  end

  defp nav_icon_paths(%{name: :sliders} = assigns) do
    ~H"""
    <path d="M4 7h10M18 7h2M4 17h4M12 17h8" /><circle cx="16" cy="7" r="2" /><circle
      cx="10"
      cy="17"
      r="2"
    />
    """
  end

  defp nav_icon_paths(%{name: :folder} = assigns) do
    ~H"""
    <path d="M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z" />
    """
  end

  defp nav_icon_paths(%{name: :inbox} = assigns) do
    ~H"""
    <path d="M4 13l2.5-7h11L20 13v5a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2z" /><path d="M4 13h4l1.5 2.5h5L16 13h4" />
    """
  end

  defp nav_icon_paths(%{name: :members} = assigns) do
    ~H"""
    <circle cx="9" cy="8" r="3.2" /><path d="M3 20c.6-3.4 3-5.4 6-5.4s5.4 2 6 5.4" /><circle
      cx="17"
      cy="9"
      r="2.4"
    /><path d="M16 14.6c2.5.2 4.4 1.9 5 5" />
    """
  end

  defp nav_icon_paths(%{name: :settings} = assigns) do
    ~H"""
    <circle cx="12" cy="12" r="3" /><path d="M19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.8-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.7 1.7 0 0 0-1.1-1.5 1.7 1.7 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.8 1.7 1.7 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.7 1.7 0 0 0 1.5-1.1 1.7 1.7 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.8.3H9a1.7 1.7 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.8V9a1.7 1.7 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1z" />
    """
  end

  # ---------------------------------------------------------------- auth shell

  @doc "The auth shell: the form on the left, the purple panel on the right."
  slot :inner_block, required: true

  def auth_shell(assigns) do
    ~H"""
    <div class="ui-auth">
      <div class="ui-auth-main">
        <a href="/" class="ui-auth-brand"><.brand_mark width={30} /><span>Emberline</span></a>
        <div class="ui-auth-card">{render_slot(@inner_block)}</div>
      </div>
      <aside class="ui-auth-side" aria-hidden="true">
        <h2>Model the system together, before anyone writes the code.</h2>
        <div class="ui-mini-em">
          <span class="c">BookOfficeHours</span><span class="c">ScheduleCall</span><span></span><span class="c">CancelBooking</span>
          <span class="e">OfficeHoursBooked</span><span class="e">CallScheduled</span><span class="e">SlotOpened</span><span class="e">BookingCancelled</span>
          <span></span><span class="r">LiveSessions</span><span></span><span class="r">MyBookings</span>
        </div>
        <ul>
          <li>
            <i>1</i><span>Drop in a clickable prototype. Get every screen as commands, events and read models.</span>
          </li>
          <li>
            <i>2</i><span>Spec it as a team: comment on any sticky, suggest scenarios, review and sign off each slice.</span>
          </li>
          <li>
            <i>3</i><span>Send ready slices to your coding agent and follow each one to a merged pull request.</span>
          </li>
        </ul>
      </aside>
    </div>
    """
  end

  @doc "The divider between sign-in options: \"or with email\"."
  slot :inner_block, required: true

  def divider(assigns) do
    ~H"""
    <div class="ui-or">{render_slot(@inner_block)}</div>
    """
  end

  # ---------------------------------------------------------------- page structure

  @doc "A page heading with an optional line under it."
  attr :title, :string, required: true
  attr :description, :string, default: nil

  def page_header(assigns) do
    ~H"""
    <div class="ui-page-head">
      <h1>{@title}</h1>
      <p :if={@description}>{@description}</p>
    </div>
    """
  end

  @doc "The settings navigation of the account and workspace pages."
  attr :current, :atom, required: true

  def settings_nav(assigns) do
    assigns =
      assign(assigns,
        account: [
          {:account_profile, "Profile", nil},
          {:account_security, "Password and security", nil},
          {:account_notifications, "Notifications", "/account/notifications"}
        ],
        workspace: [
          {:workspace_general, "General", nil},
          {:workspace_members, "Members", nil},
          {:workspace_billing, "Plan and billing", nil},
          {:workspace_integrations, "Integrations", nil}
        ]
      )

    ~H"""
    <nav class="ui-pg-nav" aria-label="Settings">
      <span class="ml">Account</span>
      <.settings_link
        :for={{key, label, href} <- @account}
        label={label}
        href={href}
        current={key == @current}
      />
      <span class="ml">Workspace</span>
      <.settings_link
        :for={{key, label, href} <- @workspace}
        label={label}
        href={href}
        current={key == @current}
      />
    </nav>
    """
  end

  attr :label, :string, required: true
  attr :href, :string, default: nil
  attr :current, :boolean, default: false

  defp settings_link(assigns) do
    ~H"""
    <a :if={@href} href={@href} aria-current={@current && "page"}>{@label}</a>
    <span :if={!@href} class="item" aria-disabled="true" title="Not built yet">{@label}</span>
    """
  end

  @doc "A card: optional header (title, description, actions), body and footer."
  attr :title, :string, default: nil
  attr :description, :string, default: nil
  attr :danger, :boolean, default: false
  attr :class, :string, default: nil
  attr :rest, :global
  slot :header_text, doc: "rich description under the title, instead of `description`"
  slot :actions
  slot :inner_block
  slot :footer

  def card(assigns) do
    ~H"""
    <section class={["ui-card", @danger && "danger", @class]} {@rest}>
      <header :if={@title}>
        <div>
          <h3>{@title}</h3>
          <p :if={@description}>{@description}</p>
          <p :if={@header_text != []}>{render_slot(@header_text)}</p>
        </div>
        <div :if={@actions != []}>{render_slot(@actions)}</div>
      </header>
      {render_slot(@inner_block)}
      <footer :if={@footer != []}>{render_slot(@footer)}</footer>
    </section>
    """
  end

  @doc "A stat tile: a number and what it counts."
  attr :value, :any, required: true
  attr :label, :string, required: true

  def stat(assigns) do
    ~H"""
    <div class="ui-stat"><b>{@value}</b><span>{@label}</span></div>
    """
  end

  @doc "An empty state: a title, a line, and an optional action."
  attr :title, :string, required: true
  slot :inner_block
  slot :action

  def empty_state(assigns) do
    ~H"""
    <div class="ui-empty">
      <b>{@title}</b>
      <span :if={@inner_block != []}>{render_slot(@inner_block)}</span>
      <div :if={@action != []}>{render_slot(@action)}</div>
    </div>
    """
  end

  # ---------------------------------------------------------------- buttons

  @doc """
  A button: `primary` or default, `danger`, `small`, `wide`. With `href`,
  `navigate` or `patch` it renders a link that looks like a button.
  """
  attr :variant, :string, values: ~w(primary default danger), default: "default"
  attr :size, :string, values: ~w(normal small), default: "normal"
  attr :wide, :boolean, default: false
  attr :class, :string, default: nil
  attr :rest, :global, include: ~w(href navigate patch method type disabled form name value)
  slot :inner_block, required: true

  def button(%{rest: rest} = assigns) do
    assigns =
      assign(assigns,
        classes: [
          "ui-btn",
          assigns.variant != "default" && assigns.variant,
          assigns.size == "small" && "small",
          assigns.wide && "wide",
          assigns.class
        ]
      )

    if rest[:href] || rest[:navigate] || rest[:patch] do
      ~H"""
      <.link class={@classes} {@rest}>{render_slot(@inner_block)}</.link>
      """
    else
      ~H"""
      <button class={@classes} {@rest}>{render_slot(@inner_block)}</button>
      """
    end
  end

  # ---------------------------------------------------------------- chips, badges, stickies

  @element_types ~w(command event read_model projection automation edge_case error none)

  @doc "A monospace chip for a model element, coloured by its type."
  attr :type, :string, values: @element_types, default: "none"
  slot :inner_block, required: true

  def chip(assigns) do
    ~H"""
    <span class={["ui-chip", @type]}>{render_slot(@inner_block)}</span>
    """
  end

  @doc "A small rounded status badge: `ok`, `acc`, `warn`, `err` or neutral."
  attr :tone, :string, values: ~w(neutral ok acc warn err), default: "neutral"
  slot :inner_block, required: true

  def badge(assigns) do
    ~H"""
    <span class={["ui-badge", @tone != "neutral" && @tone]}>{render_slot(@inner_block)}</span>
    """
  end

  @doc "A sticky note, coloured by Event Modeling element type."
  attr :type, :string,
    values: ~w(command event read_model projection automation edge_case error),
    required: true

  attr :name, :string, required: true
  attr :role, :string, default: nil
  attr :items, :list, default: []
  attr :reads, :boolean, default: false

  def sticky(assigns) do
    ~H"""
    <div class={["ui-sticky", @type, @reads && "reads"]}>
      <div :if={@role} class="role">{@role}</div>
      <div class="nm">{@name}</div>
      <ul :if={@items != []}>
        <li :for={item <- @items}>{item}</li>
      </ul>
    </div>
    """
  end

  @doc "The sticky colour legend."
  def legend(assigns) do
    ~H"""
    <div class="ui-legend" aria-label="Legend">
      <b>Legend</b>
      <span><i class="ui-sw command"></i>Command</span>
      <span><i class="ui-sw event"></i>Event</span>
      <span><i class="ui-sw projection"></i>Projection</span>
      <span><i class="ui-sw read_model"></i>Read model</span>
      <span><i class="ui-sw automation"></i>Automation</span>
      <span><i class="ui-sw error"></i>Error</span>
    </div>
    """
  end

  # ---------------------------------------------------------------- tabs

  @doc """
  Segmented tabs. Each `:tab` is a button sending `event` with `value`, or a
  link with `patch`.
  """
  attr :label, :string, required: true, doc: "accessible name of the group"

  slot :tab, required: true do
    attr :active, :boolean
    attr :event, :string
    attr :value, :string
    attr :patch, :string
    attr :count, :integer
  end

  def tabs(assigns) do
    ~H"""
    <div class="ui-seg" role="group" aria-label={@label}>
      <%= for tab <- @tab do %>
        <.link :if={tab[:patch]} patch={tab.patch} aria-selected={to_string(!!tab[:active])}>
          {render_slot(tab)}<span :if={tab[:count]} class="ct">{tab.count}</span>
        </.link>
        <button
          :if={!tab[:patch]}
          type="button"
          aria-pressed={to_string(!!tab[:active])}
          phx-click={tab[:event]}
          phx-value-tab={tab[:value]}
        >
          {render_slot(tab)}<span :if={tab[:count]} class="ct">{tab.count}</span>
        </button>
      <% end %>
    </div>
    """
  end

  @doc """
  A segmented choice that is a form field: radio buttons styled as the
  prototype's segmented control.
  """
  attr :field, Phoenix.HTML.FormField, required: true
  attr :label, :string, required: true, doc: "accessible name of the group"
  attr :options, :list, required: true, doc: "list of {label, value}"

  def segmented(assigns) do
    ~H"""
    <div class="ui-seg" role="radiogroup" aria-label={@label}>
      <label :for={{label, value} <- @options}>
        <input
          type="radio"
          name={@field.name}
          value={value}
          checked={to_string(@field.value) == value}
          class="sr-only"
        />
        <span>{label}</span>
      </label>
    </div>
    """
  end

  @doc "A sub-section of a form, marked with the accent on the left."
  attr :rest, :global
  slot :inner_block, required: true

  def subsection(assigns) do
    ~H"""
    <div class="ui-sub" {@rest}>{render_slot(@inner_block)}</div>
    """
  end

  # ---------------------------------------------------------------- drawer and dialog

  @doc "A drawer from the right edge. Rendered when `show` is true."
  attr :id, :string, required: true
  attr :show, :boolean, default: false
  attr :title, :string, required: true
  attr :subtitle, :string, default: nil
  attr :on_close, JS, default: %JS{}
  slot :inner_block, required: true

  def drawer(assigns) do
    ~H"""
    <div :if={@show} id={@id}>
      <div class="ui-drawer-layer" phx-click={@on_close}></div>
      <aside class="ui-drawer" role="dialog" aria-modal="true" aria-labelledby={"#{@id}-title"}>
        <header>
          <div>
            <h3 id={"#{@id}-title"}>{@title}</h3>
            <small :if={@subtitle}>{@subtitle}</small>
          </div>
          <button type="button" class="ui-x" phx-click={@on_close} aria-label={gettext("Close")}>✕</button>
        </header>
        <div class="body">{render_slot(@inner_block)}</div>
      </aside>
    </div>
    """
  end

  @doc "A dialog. Rendered when `show` is true."
  attr :id, :string, required: true
  attr :show, :boolean, default: false
  attr :title, :string, required: true
  attr :description, :string, default: nil
  attr :on_cancel, JS, default: %JS{}
  slot :inner_block, required: true
  slot :footer

  def dialog(assigns) do
    ~H"""
    <div :if={@show} id={@id} class="ui-mlayer" phx-window-keydown={@on_cancel} phx-key="escape">
      <div
        class="ui-modal"
        role="dialog"
        aria-modal="true"
        aria-labelledby={"#{@id}-title"}
        phx-click-away={@on_cancel}
      >
        <header>
          <div>
            <h3 id={"#{@id}-title"}>{@title}</h3>
            <p :if={@description}>{@description}</p>
          </div>
          <button type="button" class="ui-x" phx-click={@on_cancel} aria-label={gettext("Close")}>✕</button>
        </header>
        <div class="body">{render_slot(@inner_block)}</div>
        <footer :if={@footer != []}>{render_slot(@footer)}</footer>
      </div>
    </div>
    """
  end

  # ---------------------------------------------------------------- avatar

  @doc "Initials on a colour. `color` is the account's avatar colour."
  attr :name, :string, required: true
  attr :color, :string, default: nil
  attr :size, :string, values: ~w(sm md lg xl), default: "md"

  def avatar(assigns) do
    ~H"""
    <span
      class={["ui-av", @size != "md" && @size]}
      style={@color && "--c:#{@color}"}
      title={@name}
    >{initials(@name)}</span>
    """
  end

  # ---------------------------------------------------------------- form fields

  @doc "A labelled text input (or email, textarea, select) with its errors."
  attr :field, Phoenix.HTML.FormField, required: true
  attr :label, :string, required: true
  attr :type, :string, default: "text"
  attr :hint, :string, default: nil
  attr :options, :list, default: []
  attr :prompt, :string, default: nil
  attr :rest, :global, include: ~w(autocomplete placeholder rows disabled required)

  def field(%{type: "select"} = assigns) do
    assigns = assign_errors(assigns)

    ~H"""
    <label class="ui-fld" for={@field.id}>
      {@label}
      <select id={@field.id} name={@field.name} class="ui-sl" {@rest}>
        <option :if={@prompt} value="">{@prompt}</option>
        {Form.options_for_select(@options, @field.value)}
      </select>
      <.field_errors errors={@errors} />
      <p :if={@hint} class="ui-hint">{@hint}</p>
    </label>
    """
  end

  def field(%{type: "textarea"} = assigns) do
    assigns = assign_errors(assigns)

    ~H"""
    <label class="ui-fld" for={@field.id}>
      {@label}
      <textarea
        id={@field.id}
        name={@field.name}
        class="ui-in"
        aria-invalid={@errors != [] && "true"}
        {@rest}
      >{Form.normalize_value("textarea", @field.value)}</textarea>
      <.field_errors errors={@errors} />
      <p :if={@hint} class="ui-hint">{@hint}</p>
    </label>
    """
  end

  def field(%{type: "password"} = assigns) do
    assigns = assign_errors(assigns)

    ~H"""
    <label class="ui-fld" for={@field.id}>
      {@label}
      <span class="ui-pwrow">
        <input
          type="password"
          id={@field.id}
          name={@field.name}
          value={Form.normalize_value("password", @field.value)}
          class="ui-in"
          aria-invalid={@errors != [] && "true"}
          {@rest}
        />
        <button
          type="button"
          phx-click={
            JS.toggle_attribute({"type", "text", "password"}, to: "##{@field.id}")
            |> JS.toggle_attribute({"aria-pressed", "true", "false"})
          }
          aria-pressed="false"
          aria-label={"Show #{String.downcase(@label)}"}
        >Show</button>
      </span>
      <.field_errors errors={@errors} />
      <p :if={@hint} class="ui-hint">{@hint}</p>
    </label>
    """
  end

  def field(assigns) do
    assigns = assign_errors(assigns)

    ~H"""
    <label class="ui-fld" for={@field.id}>
      {@label}
      <input
        type={@type}
        id={@field.id}
        name={@field.name}
        value={Form.normalize_value(@type, @field.value)}
        class="ui-in"
        aria-invalid={@errors != [] && "true"}
        {@rest}
      />
      <.field_errors errors={@errors} />
      <p :if={@hint} class="ui-hint">{@hint}</p>
    </label>
    """
  end

  @doc "A checkbox with its label to the right."
  attr :field, Phoenix.HTML.FormField, required: true
  attr :rest, :global
  slot :inner_block, required: true

  def checkbox(assigns) do
    assigns =
      assigns
      |> assign_errors()
      |> assign(:checked, Form.normalize_value("checkbox", assigns.field.value))

    ~H"""
    <div>
      <label class="ui-chk" for={@field.id}>
        <input type="hidden" name={@field.name} value="false" />
        <input
          type="checkbox"
          id={@field.id}
          name={@field.name}
          value="true"
          checked={@checked}
          {@rest}
        />
        <span>{render_slot(@inner_block)}</span>
      </label>
      <.field_errors errors={@errors} />
    </div>
    """
  end

  @doc "An on/off switch (for settings that save straight away)."
  attr :id, :string, required: true
  attr :checked, :boolean, default: false
  attr :label, :string, required: true
  attr :rest, :global, include: ~w(disabled phx-click phx-value-kind phx-value-channel)

  def switch(assigns) do
    ~H"""
    <span class="ui-switch">
      <input type="checkbox" id={@id} checked={@checked} aria-label={@label} {@rest} /><i></i>
    </span>
    """
  end

  @doc "A form-level notice, e.g. the error from a rejected command."
  attr :tone, :string, values: ~w(note err), default: "note"
  attr :rest, :global
  slot :inner_block, required: true

  def notice(assigns) do
    ~H"""
    <p class={["ui-note", @tone == "err" && "err"]} role={@tone == "err" && "alert"} {@rest}>
      {render_slot(@inner_block)}
    </p>
    """
  end

  attr :errors, :list, required: true

  defp field_errors(assigns) do
    ~H"""
    <p :for={error <- @errors} class="ui-ferr">{error}</p>
    """
  end

  defp assign_errors(%{field: field} = assigns) do
    errors = if Phoenix.Component.used_input?(field), do: field.errors, else: []
    assign(assigns, :errors, Enum.map(errors, &translate_error/1))
  end

  # ---------------------------------------------------------------- flash

  @doc "Flash messages as toasts, bottom right."
  attr :flash, :map, required: true

  def toasts(assigns) do
    ~H"""
    <div class="ui-toasts" id="toasts" aria-live="polite">
      <div
        :for={
          {kind, message} <- [
            info: Phoenix.Flash.get(@flash, :info),
            error: Phoenix.Flash.get(@flash, :error)
          ]
        }
        :if={message}
        id={"flash-#{kind}"}
        class={["ui-toast", kind == :error && "error"]}
        role={kind == :error && "alert"}
        phx-click={JS.push("lv:clear-flash", value: %{key: kind}) |> JS.hide(to: "#flash-#{kind}")}
      >
        <p>{message}</p>
      </div>
    </div>
    """
  end

  # ---------------------------------------------------------------- helpers

  @doc "A person's name for display: their full name, or their email."
  def display_name(%{full_name: name}) when is_binary(name) and name != "", do: name
  def display_name(%{email: email}), do: to_string(email)

  @doc "Up to two initials from a name or an email."
  def initials(name) do
    name
    |> to_string()
    |> String.split("@")
    |> hd()
    |> String.split(~r/[\s._-]+/, trim: true)
    |> Enum.take(2)
    |> Enum.map_join(&String.first/1)
    |> String.upcase()
  end

  defp initial(name), do: name |> to_string() |> String.first() |> String.upcase()

  defp translate_error({msg, opts}) do
    if count = opts[:count] do
      Gettext.dngettext(EmberLineWeb.Gettext, "errors", msg, msg, count, opts)
    else
      Gettext.dgettext(EmberLineWeb.Gettext, "errors", msg, opts)
    end
  end
end
