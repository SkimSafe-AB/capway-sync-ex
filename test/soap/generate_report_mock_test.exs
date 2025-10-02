defmodule CapwaySync.Soap.GenerateReportMockTest do
  use ExUnit.Case
  alias CapwaySync.Soap.GenerateReport

  @moduletag :mock_tests

  describe "Mock SOAP responses" do
    setup do
      # Store original env value to restore later
      original_env = System.get_env("USE_MOCK_CAPWAY")
      System.put_env("USE_MOCK_CAPWAY", "true")

      on_exit(fn ->
        if original_env do
          System.put_env("USE_MOCK_CAPWAY", original_env)
        else
          System.delete_env("USE_MOCK_CAPWAY")
        end
      end)

      :ok
    end

    test "returns mock response for first page (offset 0)" do
      assert {:ok, xml_response} = GenerateReport.generate_report("test", "Data", [], offset: 0, maxrows: 100)

      assert is_binary(xml_response)
      assert String.contains?(xml_response, "GenerateReportResponse")
      assert String.contains?(xml_response, "Erik Holmqvist")
    end

    test "returns different mock response for second page (offset 100)" do
      assert {:ok, xml_response} = GenerateReport.generate_report("test", "Data", [], offset: 100, maxrows: 100)

      assert is_binary(xml_response)
      assert String.contains?(xml_response, "GenerateReportResponse")
      assert String.contains?(xml_response, "Kenneth Bandgren")
    end

    test "returns edge cases for high offset (offset 200)" do
      assert {:ok, xml_response} = GenerateReport.generate_report("test", "Data", [], offset: 200, maxrows: 100)

      assert is_binary(xml_response)
      assert String.contains?(xml_response, "i:nil=\"true\"")
      assert String.contains?(xml_response, "Åsa Öberg Ärligt")
    end

    test "returns empty response for very high offset (offset 1000)" do
      assert {:ok, xml_response} = GenerateReport.generate_report("test", "Data", [], offset: 1000, maxrows: 100)

      assert is_binary(xml_response)
      assert String.contains?(xml_response, "GenerateReportResponse")
      assert String.contains?(xml_response, "<DataRows>")
      refute String.contains?(xml_response, "ReportResults")
    end

    test "respects custom response file override" do
      System.put_env("MOCK_CAPWAY_RESPONSE", "capway_edge_cases.xml")

      assert {:ok, xml_response} = GenerateReport.generate_report("test", "Data", [], offset: 0, maxrows: 100)

      assert String.contains?(xml_response, "Åsa Öberg Ärligt")

      System.delete_env("MOCK_CAPWAY_RESPONSE")
    end

    test "handles artificial delay configuration" do
      System.put_env("MOCK_CAPWAY_DELAY", "50")

      start_time = System.monotonic_time(:millisecond)
      assert {:ok, _xml_response} = GenerateReport.generate_report("test", "Data", [], offset: 0, maxrows: 100)
      end_time = System.monotonic_time(:millisecond)

      # Should take at least 50ms
      assert end_time - start_time >= 50

      System.delete_env("MOCK_CAPWAY_DELAY")
    end

    test "returns error for missing mock file" do
      System.put_env("MOCK_CAPWAY_RESPONSE", "nonexistent_file.xml")

      assert {:error, {:mock_file_error, _reason}} = GenerateReport.generate_report("test", "Data", [], offset: 0, maxrows: 100)

      System.delete_env("MOCK_CAPWAY_RESPONSE")
    end
  end

  describe "Mock disabled" do
    setup do
      # Ensure mock is disabled
      System.delete_env("USE_MOCK_CAPWAY")
      :ok
    end

    test "uses real SOAP call when mock is disabled" do
      # This would normally make a real SOAP call, but we can't test that without credentials
      # Just verify it doesn't use the mock path
      result = GenerateReport.generate_report("test", "Data", [], offset: 0, maxrows: 100)

      # Will fail with network error since we don't have real credentials in tests
      assert {:error, _reason} = result
    end
  end

  describe "Mock data quality" do
    setup do
      System.put_env("USE_MOCK_CAPWAY", "true")
      :ok
    end

    test "mock data contains expected Swedish characters" do
      assert {:ok, xml_response} = GenerateReport.generate_report("test", "Data", [], offset: 200, maxrows: 100)

      # Should contain proper Swedish characters
      assert String.contains?(xml_response, "Åsa")
      assert String.contains?(xml_response, "Öberg")
      assert String.contains?(xml_response, "Ärligt")
    end

    test "mock data includes nil values for testing" do
      assert {:ok, xml_response} = GenerateReport.generate_report("test", "Data", [], offset: 200, maxrows: 100)

      # Should contain nil values
      assert String.contains?(xml_response, "i:nil=\"true\"")
    end

    test "mock data includes realistic Swedish personal numbers" do
      assert {:ok, xml_response} = GenerateReport.generate_report("test", "Data", [], offset: 0, maxrows: 100)

      # Should contain 12-digit personal numbers
      assert xml_response =~ ~r/\d{12}/
    end

    test "mock data includes various collection and invoice values" do
      assert {:ok, xml_response} = GenerateReport.generate_report("test", "Data", [], offset: 0, maxrows: 100)

      # Should contain numeric values for collections/invoices
      assert String.contains?(xml_response, "<Value>0</Value>")
      assert String.contains?(xml_response, "<Value>1</Value>")
      assert String.contains?(xml_response, "<Value>2</Value>")
    end
  end

  describe "Pagination simulation" do
    setup do
      System.put_env("USE_MOCK_CAPWAY", "true")
      :ok
    end

    test "different offsets return different data sets" do
      {:ok, page1} = GenerateReport.generate_report("test", "Data", [], offset: 0, maxrows: 100)
      {:ok, page2} = GenerateReport.generate_report("test", "Data", [], offset: 100, maxrows: 100)
      {:ok, page3} = GenerateReport.generate_report("test", "Data", [], offset: 200, maxrows: 100)

      # Each page should be different
      assert page1 != page2
      assert page2 != page3
      assert page1 != page3
    end

    test "maxrows parameter doesn't affect mock selection (for simplicity)" do
      {:ok, response1} = GenerateReport.generate_report("test", "Data", [], offset: 0, maxrows: 50)
      {:ok, response2} = GenerateReport.generate_report("test", "Data", [], offset: 0, maxrows: 100)

      # Same offset should return same mock file regardless of maxrows
      assert response1 == response2
    end
  end
end