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

    plug :put_secure_browser_headers, %{
      "content-security-policy" =>
        "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; font-src 'self' data:; connect-src 'self'; object-src 'none'; base-uri 'self'; form-action 'self'; frame-ancestors 'self'"
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

    ash_authentication_live_session :unauthenticated_routes,
      on_mount: [{EmberLineWeb.LiveUserAuth, :live_no_user}] do
      # Screen: signup (slice register)
      live "/register", SignupLive
    end

    auth_routes AuthController, EmberLine.Accounts.User, path: "/auth"

    sign_out_route AuthController, "/sign-out",
      overrides: [EmberLineWeb.AuthOverrides, AshAuthentication.Phoenix.Overrides.Default]

    # Remove these if you'd like to use your own authentication views
    # The signup screen (slice register) replaces the generated register page.
    sign_in_route reset_path: "/reset",
                  auth_routes_prefix: "/auth",
                  on_mount: [{EmberLineWeb.LiveUserAuth, :live_no_user}],
                  overrides: [
                    EmberLineWeb.AuthOverrides,
                    AshAuthentication.Phoenix.Overrides.Default
                  ]

    # Remove this if you do not want to use the reset password feature
    reset_route auth_routes_prefix: "/auth",
                overrides: [
                  EmberLineWeb.AuthOverrides,
                  AshAuthentication.Phoenix.Overrides.Default
                ]

    # Remove this if you do not use the confirmation strategy
    confirm_route EmberLine.Accounts.User, :confirm_new_user,
      auth_routes_prefix: "/auth",
      overrides: [EmberLineWeb.AuthOverrides, AshAuthentication.Phoenix.Overrides.Default]

    # Remove this if you do not use the magic link strategy.
    magic_sign_in_route(EmberLine.Accounts.User, :magic_link,
      auth_routes_prefix: "/auth",
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
