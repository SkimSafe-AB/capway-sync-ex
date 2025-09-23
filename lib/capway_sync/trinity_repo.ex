defmodule CapwaySync.TrinityRepo do
  use Ecto.Repo,
    otp_app: :capway_sync,
    adapter: Ecto.Adapters.Postgres
end
