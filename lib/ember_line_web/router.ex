defmodule EmberLineWeb.Router do
  use EmberLineWeb, :router

  use AshAuthentication.Phoenix.Router

  import AshAuthentication.Plug.Helpers

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {EmberLineWeb.Layouts, :root}
    plug :protect_from_forgery

    # Fonts come from Google Fonts: the stylesheet from fonts.googleapis.com,
    # the font files from fonts.gstatic.com.
    plug :put_secure_browser_headers, %{
      "content-security-policy" =>
        "default-src 'self'; script-src 'self'; style-src 'self' https://fonts.googleapis.com; img-src 'self' data:; font-src 'self' data: https://fonts.gstatic.com; connect-src 'self'; object-src 'none'; base-uri 'self'; form-action 'self'; frame-ancestors 'self'"
    }

    plug :load_from_session
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug :load_from_bearer
    plug :set_actor, :user
  end

  scope "/", EmberLineWeb do
    pipe_through :browser

    ash_authentication_live_session :authenticated_routes do
      # in each liveview, add one of the following at the top of the module:
      #
      # If an authenticated user must be present:
      # on_mount {EmberLineWeb.LiveUserAuth, :live_user_required}
      #
      # If an authenticated user *may* be present:
      # on_mount {EmberLineWeb.LiveUserAuth, :live_user_optional}
      #
      # If an authenticated user must *not* be present:
      # on_mount {EmberLineWeb.LiveUserAuth, :live_no_user}

      # Screen: projects (slices create-project, view-projects)
      live "/workspaces/:workspace_id/projects", ProjectsLive

      # Screen: account-notifications (slice set-notif-pref)
      live "/account/notifications", AccountNotificationsLive
    end
  end

  scope "/", EmberLineWeb do
    pipe_through :browser

    get "/", PageController, :home

    # Auth screens built from docs/design/screens (signin, signup, forgot,
    # forgot-sent, reset). They post to AshAuthentication's endpoints.
    ash_authentication_live_session :unauthenticated_routes,
      on_mount: [{EmberLineWeb.LiveUserAuth, :live_no_user}] do
      live "/sign-in", SignInLive
      # Screen: signup (slice register)
      live "/register", SignupLive
      live "/reset", ForgotLive
      live "/reset/sent", ForgotSentLive
      live "/password-reset/:token", ResetLive
      # Screen: verify (slice verify-email)
      live "/verify/:token", VerifyLive
    end

    post "/verify/session", VerifySessionController, :create

    auth_routes AuthController, EmberLine.Accounts.User, path: "/auth"

    # AshAuthentication pages Emberline doesn't replace, in the auth shell.
    sign_out_route AuthController, "/sign-out",
      layout: {EmberLineWeb.AuthLayout, :auth_live},
      overrides: [EmberLineWeb.AuthOverrides, AshAuthentication.Phoenix.Overrides.Default]

    confirm_route EmberLine.Accounts.User, :confirm_new_user,
      auth_routes_prefix: "/auth",
      layout: {EmberLineWeb.AuthLayout, :auth_live},
      overrides: [EmberLineWeb.AuthOverrides, AshAuthentication.Phoenix.Overrides.Default]

    magic_sign_in_route(EmberLine.Accounts.User, :magic_link,
      auth_routes_prefix: "/auth",
      layout: {EmberLineWeb.AuthLayout, :auth_live},
      overrides: [EmberLineWeb.AuthOverrides, AshAuthentication.Phoenix.Overrides.Default]
    )
  end

  # Other scopes may use custom stacks.
  # scope "/api", EmberLineWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:ember_line, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    # LiveDashboard and the mailbox preview use inline scripts and styles, so these
    # dev-only routes get a looser Content-Security-Policy than the browser pipeline.
    pipeline :dev_tools do
      plug :accepts, ["html"]
      plug :fetch_session
      plug :protect_from_forgery

      plug :put_secure_browser_headers, %{
        "content-security-policy" =>
          "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; font-src 'self' data:; connect-src 'self'; frame-src 'self'; object-src 'none'; base-uri 'self'; frame-ancestors 'self'"
      }
    end

    scope "/dev" do
      pipe_through :dev_tools

      live_dashboard "/dashboard", metrics: EmberLineWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
