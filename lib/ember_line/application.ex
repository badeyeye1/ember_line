defmodule EmberLine.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      EmberLineWeb.Telemetry,
      EmberLine.Repo,
      EmberLine.CommandedApp,
      EmberLine.Modeling.Projections.ProjectListProjection,
      {Oban, Application.fetch_env!(:ember_line, Oban)},
      {DNSCluster, query: Application.get_env(:ember_line, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: EmberLine.PubSub},
      # Start a worker by calling: EmberLine.Worker.start_link(arg)
      # {EmberLine.Worker, arg},
      # Start to serve requests, typically the last entry
      EmberLineWeb.Endpoint,
      {AshAuthentication.Supervisor, [otp_app: :ember_line]}
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: EmberLine.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    EmberLineWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
