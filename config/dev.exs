import Config

config :capway_sync, CapwaySync.TrinityRepo,
  database: "postgres",
  username: "postgres",
  password: "postgres",
  hostname: "postgres",
  pool_size: 10
