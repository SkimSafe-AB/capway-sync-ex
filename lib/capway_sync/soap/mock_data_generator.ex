defmodule CapwaySync.Soap.MockDataGenerator do
  @moduledoc """
  Utility for generating mock SOAP response data for development and testing.

  This module provides functions to generate realistic mock XML responses
  that match the Capway SOAP service structure, including Swedish names,
  personal numbers, and various edge cases.
  """

  @doc """
  Generates a complete SOAP XML response with specified number of subscribers.

  ## Options
  - `:count` - Number of subscribers to generate (default: 5)
  - `:include_nils` - Include nil values for testing (default: false)
  - `:include_edge_cases` - Include edge cases like invalid data (default: false)
  - `:swedish_chars` - Include Swedish characters in names (default: true)

  ## Example
      iex> CapwaySync.Soap.MockDataGenerator.generate_xml_response(count: 3)
      {:ok, xml_string}
  """
  def generate_xml_response(opts \\ []) do
    count = Keyword.get(opts, :count, 5)
    include_nils = Keyword.get(opts, :include_nils, false)
    include_edge_cases = Keyword.get(opts, :include_edge_cases, false)
    swedish_chars = Keyword.get(opts, :swedish_chars, true)

    subscribers = generate_subscribers(count, include_nils, include_edge_cases, swedish_chars)
    xml = build_soap_envelope(subscribers)

    {:ok, xml}
  end

  @doc """
  Writes a mock XML response to a file in the mock_responses directory.

  ## Example
      iex> CapwaySync.Soap.MockDataGenerator.write_mock_file("large_dataset.xml", count: 100)
      :ok
  """
  def write_mock_file(filename, opts \\ []) do
    {:ok, xml} = generate_xml_response(opts)

    mock_dir = Path.join([:code.priv_dir(:capway_sync), "mock_responses"])
    File.mkdir_p!(mock_dir)

    file_path = Path.join(mock_dir, filename)
    File.write!(file_path, xml)

    IO.puts("Generated mock file: #{file_path}")
    :ok
  end

  # Private functions

  defp generate_subscribers(count, include_nils, include_edge_cases, swedish_chars) do
    1..count
    |> Enum.map(fn index ->
      if include_edge_cases and rem(index, 5) == 0 do
        generate_edge_case_subscriber(index)
      else
        generate_normal_subscriber(index, include_nils, swedish_chars)
      end
    end)
  end

  defp generate_normal_subscriber(index, include_nils, swedish_chars) do
    base_id = 40000 + index * 100

    # Swedish names
    names =
      if swedish_chars do
        [
          "Erik Holmqvist",
          "Anna Åkesson",
          "Nils Åke Öberg",
          "Märta Ärligt",
          "Kenneth Bandgren",
          "Ulla Falk",
          "Carl Mannheimer",
          "Åsa Lindberg",
          "Lars Öhman",
          "Birgitta Ström",
          "Gunnar Björk",
          "Astrid Löfgren"
        ]
      else
        [
          "Erik Holmqvist",
          "Anna Akesson",
          "Nils Ake Oberg",
          "Marta Arligt",
          "Kenneth Bandgren",
          "Ulla Falk",
          "Carl Mannheimer",
          "Asa Lindberg"
        ]
      end

    name = Enum.at(names, rem(index - 1, length(names)))

    # Generate realistic Swedish personal number (YYYYMMDDNNNN)
    year = Enum.random(1950..2000)
    month = Enum.random(1..12) |> Integer.to_string() |> String.pad_leading(2, "0")
    day = Enum.random(1..28) |> Integer.to_string() |> String.pad_leading(2, "0")
    last_four = Enum.random(1000..9999)
    personal_number = "#{year}#{month}#{day}#{last_four}"

    # Generate realistic dates
    reg_date = generate_date_string(2025, 6, 1..30)
    start_date = generate_date_string(2025, 6, 15..30)

    end_date =
      if include_nils and rem(index, 3) == 0, do: nil, else: generate_date_string(2025, 7, 1..31)

    active = if rem(index, 4) == 0, do: "False", else: "True"
    paid_invoices = Enum.random(0..10)
    unpaid_invoices = Enum.random(0..5)
    collection = Enum.random(0..5)

    statuses = ["Paid", "Invoice", "Pending", "Overdue", ""]
    status = Enum.at(statuses, rem(index, length(statuses)))

    %{
      customer_ref: to_string(base_id),
      id_number: personal_number,
      name: name,
      contract_ref_no: "#{UUID.uuid4()}",
      reg_date: reg_date,
      start_date: start_date,
      end_date: end_date,
      active: active,
      paid_invoices: to_string(paid_invoices),
      unpaid_invoices: to_string(unpaid_invoices),
      collection: to_string(collection),
      last_invoice_status: status
    }
  end

  defp generate_edge_case_subscriber(index) do
    %{
      customer_ref: "99999",
      id_number: "000000000000",
      name: nil,
      contract_ref_no: nil,
      reg_date: nil,
      start_date: nil,
      end_date: nil,
      active: "False",
      paid_invoices: "0",
      unpaid_invoices: "0",
      collection: "0",
      last_invoice_status: nil
    }
  end

  defp generate_date_string(year, month, day_range) do
    day = Enum.random(day_range) |> Integer.to_string() |> String.pad_leading(2, "0")
    month_str = Integer.to_string(month) |> String.pad_leading(2, "0")
    "#{year}-#{month_str}-#{day}T00:00:00.0000000"
  end

  defp build_soap_envelope(subscribers) do
    data_rows = Enum.map(subscribers, &build_report_result/1) |> Enum.join("\n          ")

    """
    <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
      <s:Body>
        <GenerateReportResponse xmlns="urn:uuid:e657a351-ae8c-42c5-b083-ebe5dcda5c0b">
          <GenerateReportResult xmlns:i="http://www.w3.org/2001/XMLSchema-instance">
            <DataRows>
              #{data_rows}
            </DataRows>
          </GenerateReportResult>
        </GenerateReportResponse>
      </s:Body>
    </s:Envelope>
    """
  end

  defp build_report_result(subscriber) do
    fields = [
      # Always 0
      "0",
      # Always nil
      nil,
      subscriber.customer_ref,
      subscriber.id_number,
      subscriber.name,
      subscriber.contract_ref_no,
      subscriber.reg_date,
      subscriber.start_date,
      subscriber.end_date,
      subscriber.active,
      subscriber.paid_invoices,
      subscriber.unpaid_invoices,
      subscriber.collection,
      subscriber.last_invoice_status
    ]

    rows = Enum.map(fields, &build_value_element/1) |> Enum.join("\n              ")

    """
    <ReportResults>
                <Rows>
                  #{rows}
                </Rows>
              </ReportResults>
    """
  end

  defp build_value_element(nil) do
    """
    <ReportResultData>
                    <Value i:nil="true"/>
                  </ReportResultData>
    """
  end

  defp build_value_element(value) do
    escaped_value = escape_xml(to_string(value))

    """
    <ReportResultData>
                    <Value>#{escaped_value}</Value>
                  </ReportResultData>
    """
  end

  defp escape_xml(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&#39;")
  end

  # Simple UUID generation (basic implementation)
  defp uuid4 do
    :crypto.strong_rand_bytes(16)
    |> Base.encode16(case: :lower)
    |> String.replace(~r/(.{8})(.{4})(.{4})(.{4})(.{12})/, "\\1-\\2-\\3-\\4-\\5")
  end

  # Add UUID module for compatibility
  defmodule UUID do
    def uuid4, do: CapwaySync.Soap.MockDataGenerator.uuid4()
  end
end
