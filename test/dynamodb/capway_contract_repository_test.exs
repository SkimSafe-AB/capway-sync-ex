defmodule CapwaySync.Dynamodb.CapwayContractRepositoryTest do
  use ExUnit.Case, async: true

  alias CapwaySync.Dynamodb.CapwayContractRepository
  alias CapwaySync.Models.CapwaySubscriber

  defp build_subscriber(attrs \\ %{}) do
    Map.merge(
      %CapwaySubscriber{
        contract_ref_no: "contract_123",
        customer_ref: "9490",
        id_number: "195010043510",
        name: "Test Testsson",
        reg_date: "2025-10-02",
        start_date: "2025-10-02",
        end_date: nil,
        active: "true",
        paid_invoices: "4",
        unpaid_invoices: "0",
        collection: "0",
        last_invoice_status: "Paid",
        customer_id: "CID-001",
        customer_guid: "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
        contract_price: "199.00",
        next_invoice_date: "2026-04-01",
        origin: :capway,
        capway_id: "9490",
        trinity_id: nil,
        raw_data: nil
      },
      attrs
    )
  end

  describe "serialize/1" do
    test "converts subscriber to DynamoDB item map" do
      subscriber = build_subscriber()
      result = CapwayContractRepository.serialize(subscriber)

      assert result["contract_ref_no"] == "contract_123"
      assert result["customer_ref"] == "9490"
      assert result["id_number"] == "195010043510"
      assert result["name"] == "Test Testsson"
      assert result["active"] == "true"
      assert result["paid_invoices"] == "4"
      assert result["unpaid_invoices"] == "0"
      assert result["collection"] == "0"
      assert result["last_invoice_status"] == "Paid"
      assert result["customer_id"] == "CID-001"
      assert result["customer_guid"] == "a1b2c3d4-e5f6-7890-abcd-ef1234567890"
      assert result["contract_price"] == "199.00"
      assert result["next_invoice_date"] == "2026-04-01"
      assert result["reg_date"] == "2025-10-02"
      assert result["start_date"] == "2025-10-02"
      assert Map.has_key?(result, "updated_at")
    end

    test "excludes nil values" do
      subscriber = build_subscriber(%{end_date: nil})
      result = CapwayContractRepository.serialize(subscriber)

      refute Map.has_key?(result, "end_date")
    end

    test "includes end_date when present" do
      subscriber = build_subscriber(%{end_date: "2026-12-31"})
      result = CapwayContractRepository.serialize(subscriber)

      assert result["end_date"] == "2026-12-31"
    end
  end

  describe "deserialize/1" do
    test "converts DynamoDB item back to CapwaySubscriber" do
      item = %{
        "contract_ref_no" => "contract_123",
        "customer_ref" => "9490",
        "id_number" => "195010043510",
        "name" => "Test Testsson",
        "active" => "true",
        "paid_invoices" => "4",
        "unpaid_invoices" => "0",
        "collection" => "0",
        "last_invoice_status" => "Paid",
        "reg_date" => "2025-10-02",
        "start_date" => "2025-10-02",
        "customer_id" => "CID-001",
        "customer_guid" => "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
        "contract_price" => "199.00",
        "next_invoice_date" => "2026-04-01"
      }

      result = CapwayContractRepository.deserialize(item)

      assert %CapwaySubscriber{} = result
      assert result.contract_ref_no == "contract_123"
      assert result.customer_ref == "9490"
      assert result.id_number == "195010043510"
      assert result.name == "Test Testsson"
      assert result.active == "true"
      assert result.paid_invoices == "4"
      assert result.origin == :capway
      assert result.capway_id == "CID-001"
      assert result.customer_id == "CID-001"
      assert result.customer_guid == "a1b2c3d4-e5f6-7890-abcd-ef1234567890"
      assert result.contract_price == "199.00"
      assert result.next_invoice_date == "2026-04-01"
      assert result.raw_data == nil
    end

    test "handles DynamoDB typed values" do
      item = %{
        "contract_ref_no" => %{"S" => "contract_456"},
        "customer_ref" => %{"S" => "1234"},
        "id_number" => %{"S" => "199001011234"},
        "name" => %{"S" => "Anna Svensson"},
        "active" => %{"S" => "true"},
        "collection" => %{"N" => "3"},
        "end_date" => %{"NULL" => true}
      }

      result = CapwayContractRepository.deserialize(item)

      assert result.contract_ref_no == "contract_456"
      assert result.customer_ref == "1234"
      assert result.collection == "3"
      assert result.end_date == nil
    end
  end

  describe "serialize/deserialize roundtrip" do
    test "roundtrip preserves data" do
      subscriber = build_subscriber()
      serialized = CapwayContractRepository.serialize(subscriber)
      deserialized = CapwayContractRepository.deserialize(serialized)

      assert deserialized.contract_ref_no == subscriber.contract_ref_no
      assert deserialized.customer_ref == subscriber.customer_ref
      assert deserialized.id_number == subscriber.id_number
      assert deserialized.name == subscriber.name
      assert deserialized.active == subscriber.active
      assert deserialized.paid_invoices == subscriber.paid_invoices
      assert deserialized.unpaid_invoices == subscriber.unpaid_invoices
      assert deserialized.collection == subscriber.collection
      assert deserialized.last_invoice_status == subscriber.last_invoice_status
      assert deserialized.customer_id == subscriber.customer_id
      assert deserialized.customer_guid == subscriber.customer_guid
      assert deserialized.contract_price == subscriber.contract_price
      assert deserialized.next_invoice_date == subscriber.next_invoice_date
      assert deserialized.origin == :capway
    end
  end
end
