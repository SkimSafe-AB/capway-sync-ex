defmodule CapwaySync.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Starts a worker by calling: CapwaySync.Worker.start_link(arg)
      # {CapwaySync.Worker, arg}
      CapwaySync.TrinityRepo,
      CapwaySync.Vault.Trinity.AES.GCM
    ]

    # System.get_env("SYNC_REPORTS_TABLE") || raise("SYNC_REPORTS_TABLE is not set")
    # System.get_env("ACTION_ITEMS_TABLE") || raise("ACTION_ITEMS_TABLE is not set")
    required_envs()

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: CapwaySync.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp required_envs() do
    [
      "SYNC_REPORTS_TABLE",
      "ACTION_ITEMS_TABLE"
    ]
    |> Enum.each(fn env ->
      System.get_env(env) || raise("#{env} is not set")
    end)
  end
end
