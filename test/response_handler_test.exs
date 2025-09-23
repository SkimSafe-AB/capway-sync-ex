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
                      <Value>45848</Value>
                    </ReportResultData>
                    <ReportResultData>
                      <Value>Test User</Value>
                    </ReportResultData>
                    <ReportResultData>
                      <Value>195712260115</Value>
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

      assert %CapwaySubscriber{
        customer_ref: "0",
        id_number: "45848",
        name: "Test User",
        contract_ref_no: "195712260115",
        reg_date: "2025-06-22T00:00:00.0000000",
        start_date: "2025-06-29T00:00:00.0000000",
        end_date: "2025-07-01T00:00:00.0000000",
        active: "True",
        raw_data: ["0", "45848", "Test User", "195712260115", "2025-06-22T00:00:00.0000000", "2025-06-29T00:00:00.0000000", "2025-07-01T00:00:00.0000000", "True"]
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
                      <Value>195712260115</Value>
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

      assert subscriber.id_number == nil
      assert Enum.at(subscriber.raw_data, 1) == nil
      assert length(subscriber.raw_data) == 8
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
                      <Value>49246</Value>
                    </ReportResultData>
                    <ReportResultData>
                      <Value>Nils Åke Åkesson</Value>
                    </ReportResultData>
                    <ReportResultData>
                      <Value>195012013511</Value>
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
      assert subscriber.name == "Nils Åke Åkesson"
      assert is_binary(subscriber.name)
      assert String.valid?(subscriber.name)

      # Verify raw data also contains proper UTF-8
      assert Enum.at(subscriber.raw_data, 2) == "Nils Åke Åkesson"
      assert String.valid?(Enum.at(subscriber.raw_data, 2))
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
                    <ReportResultData><Value>123</Value></ReportResultData>
                    <ReportResultData><Value>User One</Value></ReportResultData>
                    <ReportResultData><Value>111111111111</Value></ReportResultData>
                    <ReportResultData><Value>2025-01-01T00:00:00.0000000</Value></ReportResultData>
                    <ReportResultData><Value>2025-01-02T00:00:00.0000000</Value></ReportResultData>
                    <ReportResultData><Value>2025-01-03T00:00:00.0000000</Value></ReportResultData>
                    <ReportResultData><Value>True</Value></ReportResultData>
                  </Rows>
                </ReportResults>
                <ReportResults>
                  <Rows>
                    <ReportResultData><Value>1</Value></ReportResultData>
                    <ReportResultData><Value>456</Value></ReportResultData>
                    <ReportResultData><Value>User Two</Value></ReportResultData>
                    <ReportResultData><Value>222222222222</Value></ReportResultData>
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
      assert first.name == "User One"
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

    test "handles extra fields beyond the defined 8 fields" do
      xml = """
      <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
        <s:Body>
          <GenerateReportResponse xmlns="urn:uuid:e657a351-ae8c-42c5-b083-ebe5dcda5c0b">
            <GenerateReportResult xmlns:i="http://www.w3.org/2001/XMLSchema-instance">
              <DataRows>
                <ReportResults>
                  <Rows>
                    <ReportResultData><Value>0</Value></ReportResultData>
                    <ReportResultData><Value>123</Value></ReportResultData>
                    <ReportResultData><Value>Test User</Value></ReportResultData>
                    <ReportResultData><Value>111111111111</Value></ReportResultData>
                    <ReportResultData><Value>2025-01-01T00:00:00.0000000</Value></ReportResultData>
                    <ReportResultData><Value>2025-01-02T00:00:00.0000000</Value></ReportResultData>
                    <ReportResultData><Value>2025-01-03T00:00:00.0000000</Value></ReportResultData>
                    <ReportResultData><Value>True</Value></ReportResultData>
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
      assert length(subscriber.raw_data) == 10
      assert Enum.at(subscriber.raw_data, 8) == "Extra Field 1"
      assert Enum.at(subscriber.raw_data, 9) == "Extra Field 2"

      # Struct should only have the first 8 fields set
      assert subscriber.active == "True"
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
                    <ReportResultData><Value>12345</Value></ReportResultData>
                    <ReportResultData><Value>Åsa Öberg Ärligt</Value></ReportResultData>
                    <ReportResultData><Value>198001011234</Value></ReportResultData>
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
      assert Enum.at(subscriber.raw_data, 2) == "Åsa Öberg Ärligt"
      assert Enum.at(subscriber.raw_data, 4) == "Göteborg"
      assert Enum.at(subscriber.raw_data, 5) == "Västerås"
      assert Enum.at(subscriber.raw_data, 6) == "Malmö"
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
                    <ReportResultData><Value>54321</Value></ReportResultData>
                    <ReportResultData><Value>Björn Längström</Value></ReportResultData>
                    <ReportResultData><Value>197012121234</Value></ReportResultData>
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
                    <ReportResultData><Value>67890</Value></ReportResultData>
                    <ReportResultData><Value>Åse-Britt Ängström-Öhman</Value></ReportResultData>
                    <ReportResultData><Value>196505051234</Value></ReportResultData>
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
      assert Enum.at(subscriber.raw_data, 2) == expected_name
      assert String.valid?(Enum.at(subscriber.raw_data, 2))
    end
  end
end