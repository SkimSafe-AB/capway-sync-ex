import Config

config :capway_sync,
  report_wsdl: System.get_env("SOAP_REPORT_WSDL") || "https://api.capway.com/Service.svc?wsdl"

config :soap, :globals, version: "1.2"

import_config "#{config_env()}.exs"
