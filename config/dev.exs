import Config

config :capway_sync, CapwaySync.TrinityRepo,
  database: "postgres",
  username: "postgres",
  password: "postgres",
  hostname: "postgres",
  pool_size: 10

# Development AWS/DynamoDB Configuration
config :ex_aws,
  # Default to us-east-1 for development
  region: System.get_env("AWS_REGION") || "us-east-1"

# Optional: Use LocalStack for local DynamoDB development
if System.get_env("USE_LOCALSTACK") == "true" do
  config :ex_aws, :dynamodb,
    scheme: "http://",
    host: System.get_env("LOCALSTACK_HOST") || "localhost",
    port: String.to_integer(System.get_env("LOCALSTACK_PORT") || "4566"),
    region: "us-east-1"
end

import_config "#{config_env()}.secret.exs"
