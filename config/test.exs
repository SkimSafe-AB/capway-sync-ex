import Config

# Test configuration
config :capway_sync,
  environment: :test,
  sync_reports_table: System.get_env("SYNC_REPORTS_TABLE") || "capway-sync-reports-test",
  # Optional: Limit pages from Capway (each page is 100 records)
  # Set CAPWAY_MAX_PAGES=6 for faster tests, defaults to unlimited if not set
  capway_max_pages: System.get_env("CAPWAY_MAX_PAGES") |> then(fn
    nil -> nil  # Default to unlimited
    "" -> nil   # Default to unlimited
    val -> String.to_integer(val)
  end)

# Test AWS/DynamoDB Configuration
# Use fake credentials for testing unless real ones are provided
config :ex_aws,
  access_key_id: System.get_env("AWS_ACCESS_KEY_ID") || "test-key",
  secret_access_key: System.get_env("AWS_SECRET_ACCESS_KEY") || "test-secret",
  region: System.get_env("AWS_REGION") || "us-east-1"

# Use LocalStack or mock endpoints for testing
config :ex_aws, :dynamodb,
  scheme: "http://",
  host: System.get_env("DYNAMODB_TEST_HOST") || "localhost",
  port: String.to_integer(System.get_env("DYNAMODB_TEST_PORT") || "4566"),
  region: "us-east-1"
