defmodule CapwaySync.Soap.ResponseHandlerTest do
  use ExUnit.Case
  alias CapwaySync.Soap.ResponseHandler
  alias CapwaySync.Models.CapwaySubscriber

  describe "ResponseHandler" do
    test "parses simple subscriber data correctly" do
      xml = """
      <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
        <s:Body>
          <GenerateReportResponse xmlns="urn:uuid:e657a351-ae8c-42c5-b083-ebe5dcda5c0b">
            <GenerateReportResult xmlns:i="http://www.w3.org/2001/XMLSchema-instance">
              <DataRows>
                <ReportResults>
                  <Rows>
                    <ReportResultData>
                      <Value>0</Value>
                    </ReportResultData>
                    <ReportResultData>
                      <Value i:nil="true"/>
                    </ReportResultData>
                    <ReportResultData>
                      <Value>45848</Value>
                    </ReportResultData>
                    <ReportResultData>
                      <Value>195712260115</Value>
                    </ReportResultData>
                    <ReportResultData>
                      <Value>Test User</Value>
                    </ReportResultData>
                    <ReportResultData>
                      <Value>CONTRACT123</Value>
                    </ReportResultData>
                    <ReportResultData>
                      <Value>2025-06-22T00:00:00.0000000</Value>
                    </ReportResultData>
                    <ReportResultData>
                      <Value>2025-06-29T00:00:00.0000000</Value>
                    </ReportResultData>
                    <ReportResultData>
                      <Value>2025-07-01T00:00:00.0000000</Value>
                    </ReportResultData>
                    <ReportResultData>
                      <Value>True</Value>
                    </ReportResultData>
                    <ReportResultData>
                      <Value>5</Value>
                    </ReportResultData>
                    <ReportResultData>
                      <Value>2</Value>
                    </ReportResultData>
                    <ReportResultData>
                      <Value>1</Value>
                    </ReportResultData>
                    <ReportResultData>
                      <Value>Invoice</Value>
                    </ReportResultData>
                  </Rows>
                </ReportResults>
              </DataRows>
            </GenerateReportResult>
          </GenerateReportResponse>
        </s:Body>
      </s:Envelope>
      """

      {:ok, subscribers} = Saxy.parse_string(xml, ResponseHandler, %{})

      assert length(subscribers) == 1
      subscriber = List.first(subscribers)

      assert %CapwaySubscriber{
        customer_ref: "45848",
        id_number: "195712260115",
        name: "Test User",
        contract_ref_no: "CONTRACT123",
        reg_date: "2025-06-22T00:00:00.0000000",
        start_date: "2025-06-29T00:00:00.0000000",
        end_date: "2025-07-01T00:00:00.0000000",
        active: "True",
        paid_invoices: "5",
        unpaid_invoices: "2",
        collection: "1",
        last_invoice_status: "Invoice",
        origin: :capway,
        raw_data: ["0", nil, "45848", "195712260115", "Test User", "CONTRACT123", "2025-06-22T00:00:00.0000000", "2025-06-29T00:00:00.0000000", "2025-07-01T00:00:00.0000000", "True", "5", "2", "1", "Invoice"]
      } = subscriber
    end

    test "handles nil values correctly" do
      xml = """
      <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
        <s:Body>
          <GenerateReportResponse xmlns="urn:uuid:e657a351-ae8c-42c5-b083-ebe5dcda5c0b">
            <GenerateReportResult xmlns:i="http://www.w3.org/2001/XMLSchema-instance">
              <DataRows>
                <ReportResults>
                  <Rows>
                    <ReportResultData>
                      <Value>0</Value>
                    </ReportResultData>
                    <ReportResultData>
                      <Value i:nil="true"/>
                    </ReportResultData>
                    <ReportResultData>
                      <Value>Test User</Value>
                    </ReportResultData>
                    <ReportResultData>
                      <Value i:nil="true"/>
                    </ReportResultData>
                    <ReportResultData>
                      <Value>User Name</Value>
                    </ReportResultData>
                    <ReportResultData>
                      <Value>CONTRACT456</Value>
                    </ReportResultData>
                    <ReportResultData>
                      <Value>2025-06-22T00:00:00.0000000</Value>
                    </ReportResultData>
                    <ReportResultData>
                      <Value>2025-06-29T00:00:00.0000000</Value>
                    </ReportResultData>
                    <ReportResultData>
                      <Value>2025-07-01T00:00:00.0000000</Value>
                    </ReportResultData>
                    <ReportResultData>
                      <Value>True</Value>
                    </ReportResultData>
                  </Rows>
                </ReportResults>
              </DataRows>
            </GenerateReportResult>
          </GenerateReportResponse>
        </s:Body>
      </s:Envelope>
      """

      {:ok, subscribers} = Saxy.parse_string(xml, ResponseHandler, %{})

      assert length(subscribers) == 1
      subscriber = List.first(subscribers)

      assert subscriber.customer_ref == "Test User"
      assert subscriber.id_number == nil
      assert subscriber.name == "User Name"
      assert Enum.at(subscriber.raw_data, 1) == nil
      assert Enum.at(subscriber.raw_data, 3) == nil
      assert length(subscriber.raw_data) == 10
    end

    test "handles UTF-8 characters correctly" do
      xml = """
      <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
        <s:Body>
          <GenerateReportResponse xmlns="urn:uuid:e657a351-ae8c-42c5-b083-ebe5dcda5c0b">
            <GenerateReportResult xmlns:i="http://www.w3.org/2001/XMLSchema-instance">
              <DataRows>
                <ReportResults>
                  <Rows>
                    <ReportResultData>
                      <Value>0</Value>
                    </ReportResultData>
                    <ReportResultData>
                      <Value i:nil="true"/>
                    </ReportResultData>
                    <ReportResultData>
                      <Value>49246</Value>
                    </ReportResultData>
                    <ReportResultData>
                      <Value>195012013511</Value>
                    </ReportResultData>
                    <ReportResultData>
                      <Value>Nils Åke Åkesson</Value>
                    </ReportResultData>
                    <ReportResultData>
                      <Value>2025-07-01T00:00:00.0000000</Value>
                    </ReportResultData>
                    <ReportResultData>
                      <Value>2025-07-30T00:00:00.0000000</Value>
                    </ReportResultData>
                    <ReportResultData>
                      <Value>2025-08-01T00:00:00.0000000</Value>
                    </ReportResultData>
                    <ReportResultData>
                      <Value>True</Value>
                    </ReportResultData>
                  </Rows>
                </ReportResults>
              </DataRows>
            </GenerateReportResult>
          </GenerateReportResponse>
        </s:Body>
      </s:Envelope>
      """

      {:ok, subscribers} = Saxy.parse_string(xml, ResponseHandler, %{})

      assert length(subscribers) == 1
      subscriber = List.first(subscribers)

      # Verify UTF-8 characters are properly decoded
      assert subscriber.customer_ref == "49246"
      assert subscriber.id_number == "195012013511"
      assert subscriber.name == "Nils Åke Åkesson"
      assert is_binary(subscriber.name)
      assert String.valid?(subscriber.name)

      # Verify raw data also contains proper UTF-8
      assert Enum.at(subscriber.raw_data, 4) == "Nils Åke Åkesson"
      assert String.valid?(Enum.at(subscriber.raw_data, 4))
    end

    test "handles multiple subscribers correctly" do
      xml = """
      <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
        <s:Body>
          <GenerateReportResponse xmlns="urn:uuid:e657a351-ae8c-42c5-b083-ebe5dcda5c0b">
            <GenerateReportResult xmlns:i="http://www.w3.org/2001/XMLSchema-instance">
              <DataRows>
                <ReportResults>
                  <Rows>
                    <ReportResultData><Value>0</Value></ReportResultData>
                    <ReportResultData><Value i:nil="true"/></ReportResultData>
                    <ReportResultData><Value>123</Value></ReportResultData>
                    <ReportResultData><Value>111111111111</Value></ReportResultData>
                    <ReportResultData><Value>User One</Value></ReportResultData>
                    <ReportResultData><Value>CONTRACT1</Value></ReportResultData>
                    <ReportResultData><Value>2025-01-01T00:00:00.0000000</Value></ReportResultData>
                    <ReportResultData><Value>2025-01-02T00:00:00.0000000</Value></ReportResultData>
                    <ReportResultData><Value>2025-01-03T00:00:00.0000000</Value></ReportResultData>
                    <ReportResultData><Value>True</Value></ReportResultData>
                  </Rows>
                </ReportResults>
                <ReportResults>
                  <Rows>
                    <ReportResultData><Value>1</Value></ReportResultData>
                    <ReportResultData><Value i:nil="true"/></ReportResultData>
                    <ReportResultData><Value>456</Value></ReportResultData>
                    <ReportResultData><Value>222222222222</Value></ReportResultData>
                    <ReportResultData><Value>User Two</Value></ReportResultData>
                    <ReportResultData><Value>CONTRACT2</Value></ReportResultData>
                    <ReportResultData><Value>2025-02-01T00:00:00.0000000</Value></ReportResultData>
                    <ReportResultData><Value>2025-02-02T00:00:00.0000000</Value></ReportResultData>
                    <ReportResultData><Value>2025-02-03T00:00:00.0000000</Value></ReportResultData>
                    <ReportResultData><Value>False</Value></ReportResultData>
                  </Rows>
                </ReportResults>
              </DataRows>
            </GenerateReportResult>
          </GenerateReportResponse>
        </s:Body>
      </s:Envelope>
      """

      {:ok, subscribers} = Saxy.parse_string(xml, ResponseHandler, %{})

      assert length(subscribers) == 2

      [first, second] = subscribers
      assert first.customer_ref == "123"
      assert first.name == "User One"
      assert second.customer_ref == "456"
      assert second.name == "User Two"
      assert first.active == "True"
      assert second.active == "False"
    end

    test "handles empty DataRows correctly" do
      xml = """
      <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
        <s:Body>
          <GenerateReportResponse xmlns="urn:uuid:e657a351-ae8c-42c5-b083-ebe5dcda5c0b">
            <GenerateReportResult xmlns:i="http://www.w3.org/2001/XMLSchema-instance">
              <DataRows>
              </DataRows>
            </GenerateReportResult>
          </GenerateReportResponse>
        </s:Body>
      </s:Envelope>
      """

      {:ok, subscribers} = Saxy.parse_string(xml, ResponseHandler, %{})

      assert subscribers == []
    end

    test "handles extra fields beyond the defined 12 fields" do
      xml = """
      <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
        <s:Body>
          <GenerateReportResponse xmlns="urn:uuid:e657a351-ae8c-42c5-b083-ebe5dcda5c0b">
            <GenerateReportResult xmlns:i="http://www.w3.org/2001/XMLSchema-instance">
              <DataRows>
                <ReportResults>
                  <Rows>
                    <ReportResultData><Value>0</Value></ReportResultData>
                    <ReportResultData><Value i:nil="true"/></ReportResultData>
                    <ReportResultData><Value>123</Value></ReportResultData>
                    <ReportResultData><Value>111111111111</Value></ReportResultData>
                    <ReportResultData><Value>Test User</Value></ReportResultData>
                    <ReportResultData><Value>CONTRACT789</Value></ReportResultData>
                    <ReportResultData><Value>2025-01-01T00:00:00.0000000</Value></ReportResultData>
                    <ReportResultData><Value>2025-01-02T00:00:00.0000000</Value></ReportResultData>
                    <ReportResultData><Value>2025-01-03T00:00:00.0000000</Value></ReportResultData>
                    <ReportResultData><Value>True</Value></ReportResultData>
                    <ReportResultData><Value>10</Value></ReportResultData>
                    <ReportResultData><Value>5</Value></ReportResultData>
                    <ReportResultData><Value>2</Value></ReportResultData>
                    <ReportResultData><Value>Paid</Value></ReportResultData>
                    <ReportResultData><Value>Extra Field 1</Value></ReportResultData>
                    <ReportResultData><Value>Extra Field 2</Value></ReportResultData>
                  </Rows>
                </ReportResults>
              </DataRows>
            </GenerateReportResult>
          </GenerateReportResponse>
        </s:Body>
      </s:Envelope>
      """

      {:ok, subscribers} = Saxy.parse_string(xml, ResponseHandler, %{})

      assert length(subscribers) == 1
      subscriber = List.first(subscribers)

      # Extra fields should be in raw_data but not affect struct fields
      assert length(subscriber.raw_data) == 16
      assert Enum.at(subscriber.raw_data, 14) == "Extra Field 1"
      assert Enum.at(subscriber.raw_data, 15) == "Extra Field 2"

      # Struct should have all defined fields set including new ones
      assert subscriber.active == "True"
      assert subscriber.paid_invoices == "10"
      assert subscriber.unpaid_invoices == "5"
      assert subscriber.collection == "2"
      assert subscriber.last_invoice_status == "Paid"
    end

    test "handles Swedish characters ÅÄÖ correctly" do
      xml = """
      <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
        <s:Body>
          <GenerateReportResponse xmlns="urn:uuid:e657a351-ae8c-42c5-b083-ebe5dcda5c0b">
            <GenerateReportResult xmlns:i="http://www.w3.org/2001/XMLSchema-instance">
              <DataRows>
                <ReportResults>
                  <Rows>
                    <ReportResultData><Value>0</Value></ReportResultData>
                    <ReportResultData><Value i:nil="true"/></ReportResultData>
                    <ReportResultData><Value>12345</Value></ReportResultData>
                    <ReportResultData><Value>198001011234</Value></ReportResultData>
                    <ReportResultData><Value>Åsa Öberg Ärligt</Value></ReportResultData>
                    <ReportResultData><Value>CONTRACT_SE</Value></ReportResultData>
                    <ReportResultData><Value>Göteborg</Value></ReportResultData>
                    <ReportResultData><Value>Västerås</Value></ReportResultData>
                    <ReportResultData><Value>Malmö</Value></ReportResultData>
                    <ReportResultData><Value>True</Value></ReportResultData>
                  </Rows>
                </ReportResults>
              </DataRows>
            </GenerateReportResult>
          </GenerateReportResponse>
        </s:Body>
      </s:Envelope>
      """

      {:ok, subscribers} = Saxy.parse_string(xml, ResponseHandler, %{})

      assert length(subscribers) == 1
      subscriber = List.first(subscribers)

      # Test all Swedish characters are properly handled
      assert subscriber.customer_ref == "12345"
      assert subscriber.id_number == "198001011234"
      assert subscriber.name == "Åsa Öberg Ärligt"
      assert subscriber.reg_date == "Göteborg"
      assert subscriber.start_date == "Västerås"
      assert subscriber.end_date == "Malmö"

      # Verify they are proper UTF-8 strings
      assert String.valid?(subscriber.name)
      assert String.valid?(subscriber.reg_date)
      assert String.valid?(subscriber.start_date)
      assert String.valid?(subscriber.end_date)

      # Verify raw data also preserves UTF-8
      assert Enum.at(subscriber.raw_data, 4) == "Åsa Öberg Ärligt"
      assert Enum.at(subscriber.raw_data, 6) == "Göteborg"
      assert Enum.at(subscriber.raw_data, 7) == "Västerås"
      assert Enum.at(subscriber.raw_data, 8) == "Malmö"
    end

    test "handles mixed Swedish characters with special cases" do
      xml = """
      <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
        <s:Body>
          <GenerateReportResponse xmlns="urn:uuid:e657a351-ae8c-42c5-b083-ebe5dcda5c0b">
            <GenerateReportResult xmlns:i="http://www.w3.org/2001/XMLSchema-instance">
              <DataRows>
                <ReportResults>
                  <Rows>
                    <ReportResultData><Value>0</Value></ReportResultData>
                    <ReportResultData><Value i:nil="true"/></ReportResultData>
                    <ReportResultData><Value>54321</Value></ReportResultData>
                    <ReportResultData><Value>197012121234</Value></ReportResultData>
                    <ReportResultData><Value>Björn Längström</Value></ReportResultData>
                    <ReportResultData><Value>CONTRACT_B</Value></ReportResultData>
                    <ReportResultData><Value>Åkersberga Höör</Value></ReportResultData>
                    <ReportResultData><Value>Ängelholm Örebro</Value></ReportResultData>
                    <ReportResultData><Value>Åre Täby</Value></ReportResultData>
                    <ReportResultData><Value>False</Value></ReportResultData>
                  </Rows>
                </ReportResults>
              </DataRows>
            </GenerateReportResult>
          </GenerateReportResponse>
        </s:Body>
      </s:Envelope>
      """

      {:ok, subscribers} = Saxy.parse_string(xml, ResponseHandler, %{})

      assert length(subscribers) == 1
      subscriber = List.first(subscribers)

      # Test mixed Swedish characters and special combinations
      assert subscriber.name == "Björn Längström"
      assert subscriber.reg_date == "Åkersberga Höör"
      assert subscriber.start_date == "Ängelholm Örebro"
      assert subscriber.end_date == "Åre Täby"

      # Verify proper encoding of special character combinations
      assert String.contains?(subscriber.name, "ö")
      assert String.contains?(subscriber.name, "ä")
      assert String.contains?(subscriber.reg_date, "Å")
      assert String.contains?(subscriber.reg_date, "ö")
      assert String.contains?(subscriber.start_date, "Ä")
      assert String.contains?(subscriber.end_date, "Å")

      # All should be valid UTF-8
      [subscriber.name, subscriber.reg_date, subscriber.start_date, subscriber.end_date]
      |> Enum.each(&assert String.valid?(&1))
    end

    test "handles complex Swedish names with multiple accented characters" do
      xml = """
      <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
        <s:Body>
          <GenerateReportResponse xmlns="urn:uuid:e657a351-ae8c-42c5-b083-ebe5dcda5c0b">
            <GenerateReportResult xmlns:i="http://www.w3.org/2001/XMLSchema-instance">
              <DataRows>
                <ReportResults>
                  <Rows>
                    <ReportResultData><Value>0</Value></ReportResultData>
                    <ReportResultData><Value i:nil="true"/></ReportResultData>
                    <ReportResultData><Value>67890</Value></ReportResultData>
                    <ReportResultData><Value>196505051234</Value></ReportResultData>
                    <ReportResultData><Value>Åse-Britt Ängström-Öhman</Value></ReportResultData>
                    <ReportResultData><Value>CONTRACT_C</Value></ReportResultData>
                    <ReportResultData><Value>Bräcke Ödeshög</Value></ReportResultData>
                    <ReportResultData><Value>Hällefors Årjäng</Value></ReportResultData>
                    <ReportResultData><Value>Töreboda Åsele</Value></ReportResultData>
                    <ReportResultData><Value>True</Value></ReportResultData>
                  </Rows>
                </ReportResults>
              </DataRows>
            </GenerateReportResult>
          </GenerateReportResponse>
        </s:Body>
      </s:Envelope>
      """

      {:ok, subscribers} = Saxy.parse_string(xml, ResponseHandler, %{})

      assert length(subscribers) == 1
      subscriber = List.first(subscribers)

      # Test complex Swedish names with hyphens and multiple accented characters
      expected_name = "Åse-Britt Ängström-Öhman"
      assert subscriber.name == expected_name
      assert String.valid?(subscriber.name)

      # Verify the name contains all expected Swedish characters
      assert String.contains?(subscriber.name, "Å")
      assert String.contains?(subscriber.name, "Ä")
      assert String.contains?(subscriber.name, "ö")
      assert String.contains?(subscriber.name, "Ö")

      # Verify reg_date contains lowercase ä
      assert String.contains?(subscriber.reg_date, "ä")

      # Test other fields with Swedish place names
      assert subscriber.reg_date == "Bräcke Ödeshög"
      assert subscriber.start_date == "Hällefors Årjäng"
      assert subscriber.end_date == "Töreboda Åsele"

      # Verify raw_data preserves encoding
      assert Enum.at(subscriber.raw_data, 4) == expected_name
      assert String.valid?(Enum.at(subscriber.raw_data, 4))
    end
  end
end