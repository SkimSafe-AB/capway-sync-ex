import Config

config :soap, :globals, version: "1.2"

# AWS Configuration
config :ex_aws,
  access_key_id: {:system, "AWS_ACCESS_KEY_ID"},
  secret_access_key: {:system, "AWS_SECRET_ACCESS_KEY"},
  region: {:system, "AWS_REGION"},
  # Optional session token for temporary credentials
  # session_token: {:system, "AWS_SESSION_TOKEN"},
  # HTTP client configuration
  http_client: ExAws.Request.Req

# DynamoDB specific configuration
config :ex_aws, :dynamodb,
  scheme: "https://",
  region: {:system, "AWS_REGION"}

import_config "#{config_env()}.exs"
