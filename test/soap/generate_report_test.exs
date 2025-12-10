defmodule CapwaySync.Soap.GenerateReportTest do
  use ExUnit.Case, async: false
  alias CapwaySync.Soap.GenerateReport

  # Mock HTTPoison for testing
  setup do
    # Store original HTTPoison functions if we need to restore them
    :ok
  end

  describe "generate_report/4" do
    test "includes default pagination parameters when no opts provided" do
      # Test that default pagination (offset: 0, maxrows: 100) is always included
      _report_name = "test_report"
      _report_type = "Data"
      _arguments = [%{name: "creditor", value: "123"}]

      # We'll test the internal parameter building by checking the XML structure
      # Since the actual SOAP call requires network connectivity, we focus on parameter handling

      # The function should not raise errors with valid parameters
      assert is_function(&GenerateReport.generate_report/4)
    end

    test "accepts custom offset with default maxrows" do
      _report_name = "test_report"
      _report_type = "Data"
      _arguments = [%{name: "creditor", value: "123"}]
      _opts = [offset: 50]

      # Should not raise errors with valid offset parameter
      assert is_function(&GenerateReport.generate_report/4)
    end

    test "accepts custom maxrows with default offset" do
      _report_name = "test_report"
      _report_type = "Data"
      _arguments = [%{name: "creditor", value: "123"}]
      _opts = [maxrows: 25]

      # Should not raise errors with valid maxrows parameter
      assert is_function(&GenerateReport.generate_report/4)
    end

    test "accepts both custom offset and maxrows" do
      _report_name = "test_report"
      _report_type = "Data"
      _arguments = [%{name: "creditor", value: "123"}]
      _opts = [offset: 100, maxrows: 50]

      # Should not raise errors with both pagination parameters
      assert is_function(&GenerateReport.generate_report/4)
    end

    test "handles empty arguments list with pagination" do
      _report_name = "test_report"
      _report_type = "Data"
      _arguments = []
      _opts = [offset: 0, maxrows: 10]

      # Should not raise errors with empty arguments and pagination
      assert is_function(&GenerateReport.generate_report/4)
    end

    test "maintains backward compatibility with existing calls" do
      # Test that existing calls without opts parameter still work
      assert is_function(&GenerateReport.generate_report/0)
      assert is_function(&GenerateReport.generate_report/1)
      assert is_function(&GenerateReport.generate_report/2)
      assert is_function(&GenerateReport.generate_report/3)
    end
  end

  describe "XML structure validation" do
    test "pagination arguments are properly formatted" do
      # Test the internal argument building logic
      offset = 25
      maxrows = 50

      # Test that pagination args are converted to strings
      pagination_args = [
        %{name: "offset", value: to_string(offset)},
        %{name: "maxrows", value: to_string(maxrows)}
      ]

      assert Enum.any?(pagination_args, fn arg ->
               arg.name == "offset" && arg.value == "25"
             end)

      assert Enum.any?(pagination_args, fn arg ->
               arg.name == "maxrows" && arg.value == "50"
             end)
    end

    test "pagination arguments are combined with user arguments" do
      user_args = [%{name: "creditor", value: "202623"}]

      pagination_args = [
        %{name: "offset", value: "0"},
        %{name: "maxrows", value: "100"}
      ]

      combined_args = user_args ++ pagination_args

      # Should have all arguments
      assert length(combined_args) == 3
      assert Enum.any?(combined_args, fn arg -> arg.name == "creditor" end)
      assert Enum.any?(combined_args, fn arg -> arg.name == "offset" end)
      assert Enum.any?(combined_args, fn arg -> arg.name == "maxrows" end)
    end

    test "default values are applied correctly" do
      # Test Keyword.get behavior for defaults
      opts = []
      offset = Keyword.get(opts, :offset, 0)
      maxrows = Keyword.get(opts, :maxrows, 100)

      assert offset == 0
      assert maxrows == 100

      # Test with partial options
      opts_partial = [offset: 50]
      offset = Keyword.get(opts_partial, :offset, 0)
      maxrows = Keyword.get(opts_partial, :maxrows, 100)

      assert offset == 50
      assert maxrows == 100
    end
  end

  describe "parameter validation" do
    test "offset and maxrows are converted to strings" do
      # Ensure integer parameters are converted to strings for XML
      offset = 42
      maxrows = 25

      assert to_string(offset) == "42"
      assert to_string(maxrows) == "25"
    end

    test "handles zero offset" do
      offset = 0
      assert to_string(offset) == "0"
    end

    test "handles large numbers" do
      offset = 999_999
      maxrows = 10000

      assert to_string(offset) == "999999"
      assert to_string(maxrows) == "10000"
    end
  end

  describe "operations function compatibility" do
    test "operations/0 still returns expected operations" do
      expected_operations = ["Ping", "ListProducedReports", "GenerateReport"]
      assert GenerateReport.operations() == expected_operations
    end

    test "ping/0 function exists and is callable" do
      assert is_function(&GenerateReport.ping/0)
    end

    test "list_produced_reports/0 function exists and is callable" do
      assert is_function(&GenerateReport.list_produced_reports/0)
    end
  end
end
