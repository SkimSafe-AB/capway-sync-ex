defmodule CapwaySync.Soap.GenerateReport do
  def init_wsdl do
    wsdl_path = Path.join([:code.priv_dir(:capway_sync), "merged_wsdl.xml"])
    {:ok, wsdl} = Soap.init_model(wsdl_path, :file, get_httpoison_opts())
    wsdl
  end

  def operations do
    # The SOAP library has issues parsing this WSDL's operations
    # Return the known operations manually based on WSDL content
    ["Ping", "ListProducedReports", "GenerateReport"]
  end

  def soap_operations do
    # Original SOAP library operations (currently returns empty list)
    init_wsdl() |> Soap.operations()
  end

  def generate_report(
        report_name \\ "CAP_q_contracts_skimsafe",
        report_type \\ "Data",
        arguments \\ [%{name: "creditor", value: "202623"}]
      ) do
    # Use custom SOAP call since the library can't parse operations from this WSDL

    params = %{
      report_name: report_name,
      report_type: report_type,
      arguments: arguments
    }

    call_soap_operation("GenerateReport", params, true)
  end

  def ping() do
    call_soap_operation("Ping", %{}, true)
  end

  def list_produced_reports() do
    call_soap_operation("ListProducedReports", %{}, true)
  end

  # Custom SOAP call function that bypasses the operation validation
  defp call_soap_operation(operation, params, auth) do
    endpoint = "https://cpw-wip01.prod.aptichosting.net:8318/Reporting/"
    namespace = "urn:uuid:e657a351-ae8c-42c5-b083-ebe5dcda5c0b"
    soap_action = "#{namespace}/Reporting/#{operation}"

    # Build SOAP envelope
    soap_body = build_soap_envelope(operation, params, namespace)

    headers = [
      {"Content-Type", "text/xml; charset=utf-8"},
      {"SOAPAction", soap_action}
    ]

    # Add authentication if needed
    http_options = get_httpoison_opts(auth)

    case HTTPoison.post(endpoint, soap_body, headers, http_options) do
      {:ok, response} ->
        case response.status_code do
          200 -> {:ok, response.body}
          401 -> {:error, :unauthorized}
          _ -> {:error, {:http_error, response.status_code, response.body}}
        end

      {:error, error} ->
        {:error, error}
    end
  end

  defp build_soap_envelope(operation, params, namespace) do
    body_content =
      case operation do
        "GenerateReport" -> build_generate_report_body(params, namespace)
        _ -> ""
      end

    "<soapenv:Envelope xmlns:soapenv=\"http://schemas.xmlsoap.org/soap/envelope/\" xmlns:urn=\"" <>
      namespace <>
      "\">" <>
      "\n  <soapenv:Header>" <>
      "\n    <urn:SessionHeader/>" <>
      "\n  </soapenv:Header>" <>
      "\n  <soapenv:Body>" <>
      "\n    <urn:" <>
      operation <>
      ">" <>
      body_content <>
      "\n    </urn:" <>
      operation <>
      ">" <>
      "\n  </soapenv:Body>" <>
      "\n</soapenv:Envelope>"
  end

  defp build_generate_report_body(params, _namespace) do
    report_name = Map.get(params, :report_name, "CAP_q_contracts_skimsafe")
    report_type = Map.get(params, :report_type, "Data")
    arguments = Map.get(params, :arguments, [])

    # Build arguments structure
    arguments_xml =
      if Enum.empty?(arguments) do
        ""
      else
        argument_values =
          arguments
          |> Enum.map(fn arg ->
            name = Map.get(arg, :name, "")
            value = Map.get(arg, :value, "")

            "\n              <urn:ReportArgumentValue>" <>
              "\n                <urn:Name>" <>
              name <>
              "</urn:Name>" <>
              "\n                <urn:Value>" <>
              value <>
              "</urn:Value>" <>
              "\n              </urn:ReportArgumentValue>"
          end)
          |> Enum.join("")

        "\n        <urn:Arguments>" <> argument_values <> "\n        </urn:Arguments>"
      end

    "\n      <urn:ReportRequest>" <>
      arguments_xml <>
      "\n        <urn:ReportName>" <>
      report_name <>
      "</urn:ReportName>" <>
      "\n        <urn:ReportType>" <>
      report_type <>
      "</urn:ReportType>" <>
      "\n      </urn:ReportRequest>"
  end

  defp get_httpoison_opts(auth \\ false) do
    hackney_base_opts = [:insecure]

    hackney_opts =
      hackney_base_opts ++
        if auth,
          do: [basic_auth: add_auth(), insecure_basic_auth: true],
          else: [basic_auth: nil]

    [
      hackney: hackney_opts
    ]
  end

  defp add_auth do
    {
      System.get_env("SOAP_USERNAME"),
      System.get_env("SOAP_PASSWORD")
    }
  end
end
