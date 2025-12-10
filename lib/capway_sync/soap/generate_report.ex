defmodule CapwaySync.Soap.GenerateReport do
  def init_wsdl do
    wsdl_path = Path.join([:code.priv_dir(:capway_sync), "merged_wsdl.xml"])
    # Note: SOAP library isn't used for actual requests, but keep for compatibility
    soap_opts = [hackney: [:insecure, recv_timeout: 30_000, timeout: 30_000]]
    {:ok, wsdl} = Soap.init_model(wsdl_path, :file, soap_opts)
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

  @doc """
  Generate a report with pagination support.

  ## Parameters
    - report_name: Name of the report to generate (default: "CAP_q_contracts_skimsafe")
    - report_type: Type of report (default: "Data")
    - arguments: Arguments list (default: [%{name: "creditor", value: "202623"}])
    - opts: Optional keyword list with pagination parameters
      - offset: Starting position for pagination (default: 0)
      - maxrows: Maximum number of rows to return (default: 100)

  ## Examples
      # Default pagination (offset: 0, maxrows: 100)
      iex> CapwaySync.Soap.GenerateReport.generate_report()
      {:ok, soap_response}

      # Custom offset with default maxrows
      iex> CapwaySync.Soap.GenerateReport.generate_report("MyReport", "Data", [], offset: 50)
      {:ok, soap_response}

      # Custom pagination
      iex> CapwaySync.Soap.GenerateReport.generate_report("MyReport", "Data", [], offset: 0, maxrows: 25)
      {:ok, soap_response}
  """
  def generate_report(
        report_name \\ "CAP_q_contracts_skimsafe",
        report_type \\ "Data",
        arguments \\ [%{name: "creditor", value: "202623"}],
        opts \\ []
      ) do
    # Check if mock mode is enabled
    if System.get_env("USE_MOCK_CAPWAY") == "true" do
      # Extract pagination parameters for mock selection
      offset = Keyword.get(opts, :offset, 0)
      maxrows = Keyword.get(opts, :maxrows, 100)

      get_mock_response(offset, maxrows)
    else
      # Use custom SOAP call since the library can't parse operations from this WSDL

      # Extract pagination parameters with defaults
      offset = Keyword.get(opts, :offset, 0)
      maxrows = Keyword.get(opts, :maxrows, 100)

      # Build pagination arguments
      pagination_args = [
        %{name: "offset", value: to_string(offset)},
        %{name: "maxrows", value: to_string(maxrows)}
      ]

      # Combine with user arguments
      final_arguments = arguments ++ pagination_args

      params = %{
        report_name: report_name,
        report_type: report_type,
        arguments: final_arguments
      }

      call_soap_operation("GenerateReport", params, true)
    end
  end

  @doc """
  Pings the SOAP service to check connectivity.
  """
  @spec ping() :: {:ok, String.t()} | {:error, any()}
  def ping() do
    call_soap_operation("Ping", %{}, true)
  end

  @doc """
  Lists produced reports from the SOAP service.
  """
  @spec list_produced_reports() :: {:ok, String.t()} | {:error, any()}
  def list_produced_reports() do
    call_soap_operation("ListProducedReports", %{}, true)
  end

  # Returns mock SOAP response data for development and testing.
  #
  # Mock responses are selected based on offset to simulate pagination:
  # - offset 0: First page with normal data (capway_page_1.xml)
  # - offset >= 100: Second page with different data (capway_page_2.xml)
  # - offset >= 200: Edge cases with nil values and encoding (capway_edge_cases.xml)
  # - offset >= 1000: Empty response (capway_empty.xml)
  #
  # ## Environment Variables
  # - `MOCK_CAPWAY_RESPONSE`: Override specific response file
  # - `MOCK_CAPWAY_DELAY`: Add artificial delay in milliseconds
  defp get_mock_response(offset, _maxrows) do
    # Check for custom response override
    custom_response = System.get_env("MOCK_CAPWAY_RESPONSE")

    mock_file =
      cond do
        custom_response -> custom_response
        offset >= 1000 -> "capway_empty.xml"
        offset >= 200 -> "capway_edge_cases.xml"
        offset >= 100 -> "capway_page_2.xml"
        true -> "capway_page_1.xml"
      end

    # Add artificial delay if configured
    if delay = System.get_env("MOCK_CAPWAY_DELAY") do
      delay_ms = String.to_integer(delay)
      Process.sleep(delay_ms)
    end

    mock_path = Path.join([:code.priv_dir(:capway_sync), "mock_responses", mock_file])

    case File.read(mock_path) do
      {:ok, content} ->
        require Logger
        Logger.info("🎭 Using mock Capway response: #{mock_file} (offset: #{offset})")
        {:ok, content}

      {:error, reason} ->
        require Logger
        Logger.error("❌ Failed to read mock response #{mock_file}: #{inspect(reason)}")
        {:error, {:mock_file_error, reason}}
    end
  end

  # Custom SOAP call function that bypasses the operation validation
  defp call_soap_operation(operation, params, auth) do
    endpoint = "https://c001217-8310-p-wip.prod.hosting.aptic.cloud:8318/Reporting/"
    namespace = "urn:uuid:e657a351-ae8c-42c5-b083-ebe5dcda5c0b"
    soap_action = "#{namespace}/Reporting/#{operation}"

    # Build SOAP envelope
    soap_body = build_soap_envelope(operation, params, namespace)

    # Build Req options
    req_options = get_req_options(auth, soap_action)

    call_soap_with_retry(endpoint, soap_body, req_options, 3)
  end

  defp call_soap_with_retry(endpoint, soap_body, req_options, retries_left) do
    require Logger

    case Req.post(endpoint, [body: soap_body] ++ req_options) do
      {:ok, response} ->
        case response.status do
          200 ->
            File.write("priv/soap_response.xml", response.body)
            {:ok, response.body}

          401 ->
            Logger.error("SOAP authentication failed - unauthorized")
            {:error, :unauthorized}

          status when status in [502, 503, 504] and retries_left > 0 ->
            Logger.warning(
              "SOAP server error (#{status}), retrying... (#{retries_left} retries left)"
            )

            Process.sleep(1000 * (4 - retries_left))
            call_soap_with_retry(endpoint, soap_body, req_options, retries_left - 1)

          status when status in [429] and retries_left > 0 ->
            Logger.warning(
              "SOAP rate limited (#{status}), retrying... (#{retries_left} retries left)"
            )

            Process.sleep(2000 * (4 - retries_left))
            call_soap_with_retry(endpoint, soap_body, req_options, retries_left - 1)

          _ ->
            Logger.error("SOAP request failed with status #{response.status}")
            {:error, {:http_error, response.status, response.body}}
        end

      {:error, %{reason: :timeout}} when retries_left > 0 ->
        Logger.warning("SOAP request timeout, retrying... (#{retries_left} retries left)")
        Process.sleep(2000 * (4 - retries_left))
        call_soap_with_retry(endpoint, soap_body, req_options, retries_left - 1)

      {:error, %{reason: reason}}
      when reason in [:econnrefused, :nxdomain, :closed] and retries_left > 0 ->
        Logger.warning(
          "SOAP connection error (#{reason}), retrying... (#{retries_left} retries left)"
        )

        Process.sleep(1500 * (4 - retries_left))
        call_soap_with_retry(endpoint, soap_body, req_options, retries_left - 1)

      {:error, error} ->
        Logger.error("SOAP request failed: #{inspect(error)}")
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

  defp get_req_options(auth, soap_action) do
    base_options = [
      headers: [
        {"Content-Type", "text/xml; charset=utf-8"},
        {"SOAPAction", soap_action}
      ],
      receive_timeout: 180_000,
      connect_options: [
        timeout: 180_000,
        transport_opts: [verify: :verify_none]
      ]
    ]

    if auth do
      username = System.get_env("SOAP_USERNAME")
      password = System.get_env("SOAP_PASSWORD")

      if username && password do
        base_options ++ [auth: {:basic, "#{username}:#{password}"}]
      else
        base_options
      end
    else
      base_options
    end
  end
end
