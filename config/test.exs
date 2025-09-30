import Config

# Test configuration
config :capway_sync,
  environment: :test,
  sync_reports_table: System.get_env("SYNC_REPORTS_TABLE") || "capway-sync-reports-test"

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