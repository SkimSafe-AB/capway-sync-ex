defmodule CapwaySync.Reactor.V1.Steps.CapwayExportSubscribersTest do
  use ExUnit.Case, async: true
  alias CapwaySync.Reactor.V1.Steps.CapwayExportSubscribers

  describe "filter_subscribers_for_export/1" do
    test "filters subscribers with unpaid invoices > 0" do
      subscribers = [
        %{id_number: "123", unpaid_invoices: 2, collection: 0},
        %{id_number: "456", unpaid_invoices: 0, collection: 0},
        %{id_number: "789", unpaid_invoices: 1, collection: 0}
      ]

      result = CapwayExportSubscribers.filter_subscribers_for_export(subscribers)

      assert length(result) == 2
      assert Enum.any?(result, &(&1.id_number == "123"))
      assert Enum.any?(result, &(&1.id_number == "789"))
      refute Enum.any?(result, &(&1.id_number == "456"))
    end

    test "filters subscribers with collections > 0" do
      subscribers = [
        %{id_number: "123", unpaid_invoices: 0, collection: 1},
        %{id_number: "456", unpaid_invoices: 0, collection: 0},
        %{id_number: "789", unpaid_invoices: 0, collection: 3}
      ]

      result = CapwayExportSubscribers.filter_subscribers_for_export(subscribers)

      assert length(result) == 2
      assert Enum.any?(result, &(&1.id_number == "123"))
      assert Enum.any?(result, &(&1.id_number == "789"))
      refute Enum.any?(result, &(&1.id_number == "456"))
    end

    test "filters subscribers with both unpaid invoices and collections" do
      subscribers = [
        %{id_number: "123", unpaid_invoices: 2, collection: 1},
        %{id_number: "456", unpaid_invoices: 0, collection: 0},
        %{id_number: "789", unpaid_invoices: 1, collection: 2}
      ]

      result = CapwayExportSubscribers.filter_subscribers_for_export(subscribers)

      assert length(result) == 2
      assert Enum.any?(result, &(&1.id_number == "123"))
      assert Enum.any?(result, &(&1.id_number == "789"))
      refute Enum.any?(result, &(&1.id_number == "456"))
    end

    test "handles nil values gracefully" do
      subscribers = [
        %{id_number: "123", unpaid_invoices: nil, collection: 1},
        %{id_number: "456", unpaid_invoices: 2, collection: nil},
        %{id_number: "789", unpaid_invoices: nil, collection: nil}
      ]

      result = CapwayExportSubscribers.filter_subscribers_for_export(subscribers)

      assert length(result) == 2
      assert Enum.any?(result, &(&1.id_number == "123"))
      assert Enum.any?(result, &(&1.id_number == "456"))
      refute Enum.any?(result, &(&1.id_number == "789"))
    end

    test "returns empty list when no subscribers meet criteria" do
      subscribers = [
        %{id_number: "123", unpaid_invoices: 0, collection: 0},
        %{id_number: "456", unpaid_invoices: 0, collection: 0}
      ]

      result = CapwayExportSubscribers.filter_subscribers_for_export(subscribers)

      assert result == []
    end
  end

  describe "generate_csv_content/1" do
    test "generates CSV with header and rows" do
      subscribers = [
        %{id_number: "123456789", name: "John Doe", customer_ref: "CR001", unpaid_invoices: 2, collection: 1},
        %{id_number: "987654321", name: "Jane Smith", customer_ref: "CR002", unpaid_invoices: 0, collection: 3}
      ]

      result = CapwayExportSubscribers.generate_csv_content(subscribers)

      assert String.starts_with?(result, "id_number,name,customer_ref,email,unpaid_invoices,collection\n")
      assert String.contains?(result, "123456789,John Doe,CR001,,2,1\n")
      assert String.contains?(result, "987654321,Jane Smith,CR002,,0,3\n")
    end

    test "generates empty CSV with only header for empty list" do
      result = CapwayExportSubscribers.generate_csv_content([])

      assert result == "id_number,name,customer_ref,email,unpaid_invoices,collection\n"
    end
  end

  describe "subscriber_to_csv_row/1" do
    test "converts subscriber to CSV row with all fields" do
      subscriber = %{
        id_number: "123456789",
        name: "John Doe",
        customer_ref: "CR001",
        unpaid_invoices: 2,
        collection: 1
      }

      result = CapwayExportSubscribers.subscriber_to_csv_row(subscriber)

      assert result == "123456789,John Doe,CR001,,2,1\n"
    end

    test "handles missing fields gracefully" do
      subscriber = %{
        id_number: "123456789"
      }

      result = CapwayExportSubscribers.subscriber_to_csv_row(subscriber)

      assert result == "123456789,,,,0,0\n"
    end

    test "escapes name field with commas" do
      subscriber = %{
        id_number: "123456789",
        name: "Doe, John",
        customer_ref: "CR001",
        unpaid_invoices: 2,
        collection: 1
      }

      result = CapwayExportSubscribers.subscriber_to_csv_row(subscriber)

      assert result == "123456789,\"Doe, John\",CR001,,2,1\n"
    end

    test "handles nil values" do
      subscriber = %{
        id_number: "123456789",
        name: nil,
        customer_ref: nil,
        unpaid_invoices: nil,
        collection: nil
      }

      result = CapwayExportSubscribers.subscriber_to_csv_row(subscriber)

      assert result == "123456789,,,,0,0\n"
    end
  end

  describe "escape_csv_field/1" do
    test "returns empty string for nil" do
      assert CapwayExportSubscribers.escape_csv_field(nil) == ""
    end

    test "returns empty string for empty string" do
      assert CapwayExportSubscribers.escape_csv_field("") == ""
    end

    test "returns field unchanged if no special characters" do
      assert CapwayExportSubscribers.escape_csv_field("John Doe") == "John Doe"
    end

    test "wraps field in quotes if contains comma" do
      assert CapwayExportSubscribers.escape_csv_field("Doe, John") == "\"Doe, John\""
    end

    test "escapes quotes and wraps in quotes" do
      assert CapwayExportSubscribers.escape_csv_field("John \"Johnny\" Doe") == "\"John \"\"Johnny\"\" Doe\""
    end

    test "wraps field in quotes if contains newline" do
      assert CapwayExportSubscribers.escape_csv_field("John\nDoe") == "\"John\nDoe\""
    end

    test "converts non-string to string" do
      assert CapwayExportSubscribers.escape_csv_field(123) == "123"
    end
  end

  describe "count_subscribers_with_unpaid_invoices/1" do
    test "counts subscribers with unpaid invoices > 0" do
      subscribers = [
        %{unpaid_invoices: 2},
        %{unpaid_invoices: 0},
        %{unpaid_invoices: 1},
        %{unpaid_invoices: nil}
      ]

      result = CapwayExportSubscribers.count_subscribers_with_unpaid_invoices(subscribers)

      assert result == 2
    end
  end

  describe "count_subscribers_with_collections/1" do
    test "counts subscribers with collections > 0" do
      subscribers = [
        %{collection: 1},
        %{collection: 0},
        %{collection: 3},
        %{collection: nil}
      ]

      result = CapwayExportSubscribers.count_subscribers_with_collections(subscribers)

      assert result == 2
    end
  end

  describe "run/3" do
    test "returns error for missing capway_data argument" do
      result = CapwayExportSubscribers.run(%{}, %{}, [])

      assert {:error, "Missing required argument: capway_data"} = result
    end

    test "returns error for non-list capway_data argument" do
      result = CapwayExportSubscribers.run(%{capway_data: "not a list"}, %{}, [])

      assert {:error, "Argument capway_data must be a list"} = result
    end

    test "handles empty capway_data list" do
      result = CapwayExportSubscribers.run(%{capway_data: []}, %{}, [])

      assert {:ok, %{total_exported: 0, customers_with_unpaid_invoices: 0, customers_with_collections: 0}} = result
    end
  end
end