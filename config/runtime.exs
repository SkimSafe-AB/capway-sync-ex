import Config
require Logger

market_env = System.get_env("MARKET")

if is_nil(market_env) and config_env() != :test do
  raise "MARKET environment variable is not set (e.g. \"se\")"
end

# Normalise the casing so deploy manifests can use either "SE"/"NO" or
# "se"/"no" — the market is keyed on lowercase atoms (`:se`, `:no`) everywhere
# (CapwaySync.Market settings, the personnummer validity gate, etc.).
config :capway_sync, :market, market_env |> Kernel.||("se") |> String.downcase() |> String.to_atom()

config :capway_sync, Trinity.Db.Hashed.HMAC,
  algorithm: :sha512,
  secret: System.get_env("TRINITY_HASHED_HMAC")

if config_env() != :test do
  config :capway_sync, :rest_api,
    base_url: System.get_env("REST_API_BASE_URL") || raise("REST_API_BASE_URL is not set"),
    username: System.get_env("REST_API_USERNAME") || raise("REST_API_USERNAME is not set"),
    password: System.get_env("REST_API_PASSWORD") || raise("REST_API_PASSWORD is not set")

  config :capway_sync, :payment_processor,
    host:
      System.get_env("PAYMENT_PROCESSOR_HOST") ||
        raise("PAYMENT_PROCESSOR_HOST is not set (must end with `/`)")
end

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

  config :ex_aws,
    secret_access_key: [{:awscli, "profile_name", 30}],
    access_key_id: [{:awscli, "profile_name", 30}],
    awscli_auth_adapter: ExAws.STS.AuthCache.AssumeRoleWebIdentityAdapter,
    region: System.get_env("AWS_REGION")

  if log_level = System.get_env("LOG_LEVEL") do
    config :logger, level: String.to_atom(log_level)
  end

  config :logger, :default_handler,
    formatter: LoggerJSON.Formatters.Basic.new(metadata: [:request_id])

  config :capway_sync,
    report_wsdl: System.get_env("SOAP_REPORT_WSDL"),
    sync_reports_table: System.get_env("SYNC_REPORTS_TABLE"),
    action_items_table: System.get_env("ACTION_ITEMS_TABLE"),
    capway_cache_table: System.get_env("CAPWAY_CACHE_TABLE"),
    # Creditor id passed to the Capway report query. Set per-client via the
    # CAPWAY_CREDITOR env var.
    capway_creditor: System.get_env("CAPWAY_CREDITOR"),
    # Max pages to fetch from Capway (each page is 100 records)
    # Set to nil or 0 for unlimited, or a positive integer for limit
    capway_max_pages:
      System.get_env("CAPWAY_MAX_PAGES")
      |> then(fn
        nil -> nil
        "" -> nil
        val -> String.to_integer(val)
      end)
end
