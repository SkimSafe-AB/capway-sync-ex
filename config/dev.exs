import Config

config :capway_sync, CapwaySync.TrinityRepo,
  database: "postgres",
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  pool_size: 10
