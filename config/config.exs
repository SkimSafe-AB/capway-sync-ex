import Config

config :capway_sync,
  report_wsdl: System.get_env("SOAP_REPORT_WSDL") || "https://api.capway.com/Service.svc?wsdl",
  sync_reports_table:
    System.get_env("SYNC_REPORTS_TABLE") ||
      raise("SYNC_REPORTS_TABLE is not set"),
  action_items_table:
    System.get_env("ACTION_ITEMS_TABLE") || raise("ACTION_ITEMS_TABLE is not set")

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

# Optional: Override DynamoDB endpoint (useful for localstack/development)
# host: {:system, "DYNAMODB_HOST"}

import_config "#{config_env()}.exs"
