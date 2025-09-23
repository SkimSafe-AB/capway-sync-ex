import Config

if System.get_env("TRINITY_DB_VAULT_KEY") do
  config :capway_sync, Trinity.Db.Vault,
    ciphers: [
      default:
        {Cloak.Ciphers.AES.GCM,
         tag: "AES.GCM.V1", key: Base.decode64!(System.get_env("TRINITY_DB_VAULT_KEY"))},
      retired:
        {Cloak.Ciphers.AES.GCM,
         tag: "AES.GCM.V1", key: Base.decode64!(System.get_env("TRINITY_DB_VAULT_KEY_RETIRED"))}
    ]
end

config :capway_sync, Trinity.Db.Hashed.HMAC,
  algorithm: :sha512,
  secret: System.get_env("TRINITY_HASHED_HMAC")

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6"), do: [:inet6], else: []

  config :capway_sync, CapwaySync.TrinityRepo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "20"),
    socket_options: maybe_ipv6,
    show_sensitive_data_on_connection_error: true,
    ssl: true,
    ssl_opts: [
      # For RDS, this is usually sufficient
      verify: :verify_none
    ]
end
