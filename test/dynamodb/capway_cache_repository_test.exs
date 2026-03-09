defmodule CapwaySync.Dynamodb.CapwayCacheRepositoryTest do
  use ExUnit.Case, async: true

  alias CapwaySync.Dynamodb.CapwayCacheRepository
  alias CapwaySync.Models.CapwaySubscriber

  describe "chunk_size/0" do
    test "returns 200" do
      assert CapwayCacheRepository.chunk_size() == 200
    end
  end

  describe "chunking logic" do
    test "550 subscribers produce 3 chunks of 200, 200, 150" do
      subscribers = build_subscribers(550)
      chunks = Enum.chunk_every(subscribers, CapwayCacheRepository.chunk_size())

      assert length(chunks) == 3
      assert length(Enum.at(chunks, 0)) == 200
      assert length(Enum.at(chunks, 1)) == 200
      assert length(Enum.at(chunks, 2)) == 150
    end

    test "200 subscribers produce exactly 1 chunk" do
      subscribers = build_subscribers(200)
      chunks = Enum.chunk_every(subscribers, CapwayCacheRepository.chunk_size())

      assert length(chunks) == 1
      assert length(Enum.at(chunks, 0)) == 200
    end

    test "empty list produces no chunks" do
      chunks = Enum.chunk_every([], CapwayCacheRepository.chunk_size())

      assert chunks == []
    end

    test "1 subscriber produces 1 chunk of 1" do
      subscribers = build_subscribers(1)
      chunks = Enum.chunk_every(subscribers, CapwayCacheRepository.chunk_size())

      assert length(chunks) == 1
      assert length(Enum.at(chunks, 0)) == 1
    end
  end

  describe "build_manifest/2" do
    test "creates manifest with correct counts for 550 subscribers" do
      subscribers = build_subscribers(550)
      manifest = CapwayCacheRepository.build_manifest("2026-03-09", subscribers)

      assert manifest["cache_date"] == "2026-03-09"
      assert manifest["chunk_id"] == "manifest"
      assert manifest["total_subscribers"] == 550
      assert manifest["chunk_count"] == 3
      assert is_binary(manifest["created_at"])
      assert is_integer(manifest["ttl"])
      assert manifest["ttl"] > DateTime.utc_now() |> DateTime.to_unix()
    end

    test "creates manifest with correct counts for empty list" do
      manifest = CapwayCacheRepository.build_manifest("2026-03-09", [])

      assert manifest["total_subscribers"] == 0
      assert manifest["chunk_count"] == 0
    end

    test "creates manifest with correct date" do
      subscribers = build_subscribers(10)
      manifest = CapwayCacheRepository.build_manifest("2026-01-15", subscribers)

      assert manifest["cache_date"] == "2026-01-15"
    end
  end

  describe "serialize_subscriber/1" do
    test "converts CapwaySubscriber struct to string-keyed map" do
      subscriber = %CapwaySubscriber{
        customer_ref: "CR001",
        id_number: "1234567890",
        name: "Test User",
        contract_ref_no: "CON001",
        reg_date: "2026-01-01",
        start_date: "2026-01-01",
        end_date: nil,
        active: "1",
        paid_invoices: "5",
        unpaid_invoices: "0",
        collection: "0",
        last_invoice_status: "paid",
        origin: "capway",
        trinity_id: "T001",
        capway_id: "C001",
        raw_data: %{some: "large data"}
      }

      result = CapwayCacheRepository.serialize_subscriber(subscriber)

      assert result["customer_ref"] == "CR001"
      assert result["id_number"] == "1234567890"
      assert result["name"] == "Test User"
      assert result["active"] == "1"
      assert result["origin"] == "capway"
      refute Map.has_key?(result, "raw_data")
      refute Map.has_key?(result, :customer_ref)
    end

    test "handles nil fields" do
      subscriber = %CapwaySubscriber{
        customer_ref: nil,
        id_number: "1234567890",
        name: nil
      }

      result = CapwayCacheRepository.serialize_subscriber(subscriber)

      assert result["id_number"] == "1234567890"
      assert result["customer_ref"] == nil
      assert result["name"] == nil
    end
  end

  describe "deserialize_subscriber/1" do
    test "converts string-keyed map back to CapwaySubscriber struct" do
      map = %{
        "customer_ref" => "CR001",
        "id_number" => "1234567890",
        "name" => "Test User",
        "contract_ref_no" => "CON001",
        "reg_date" => "2026-01-01",
        "start_date" => "2026-01-01",
        "end_date" => nil,
        "active" => "1",
        "paid_invoices" => "5",
        "unpaid_invoices" => "0",
        "collection" => "0",
        "last_invoice_status" => "paid",
        "origin" => "capway",
        "trinity_id" => "T001",
        "capway_id" => "C001"
      }

      result = CapwayCacheRepository.deserialize_subscriber(map)

      assert %CapwaySubscriber{} = result
      assert result.customer_ref == "CR001"
      assert result.id_number == "1234567890"
      assert result.name == "Test User"
      assert result.active == "1"
      assert result.raw_data == nil
    end

    test "round-trip serialization preserves data" do
      original = %CapwaySubscriber{
        customer_ref: "CR001",
        id_number: "1234567890",
        name: "Åsa Öberg",
        contract_ref_no: "CON001",
        reg_date: "2026-01-01",
        start_date: "2026-01-01",
        end_date: "2026-12-31",
        active: "1",
        paid_invoices: "5",
        unpaid_invoices: "2",
        collection: "1",
        last_invoice_status: "unpaid",
        origin: "capway",
        trinity_id: "T001",
        capway_id: "C001",
        raw_data: %{should: "be excluded"}
      }

      result =
        original
        |> CapwayCacheRepository.serialize_subscriber()
        |> CapwayCacheRepository.deserialize_subscriber()

      assert result.customer_ref == original.customer_ref
      assert result.id_number == original.id_number
      assert result.name == original.name
      assert result.contract_ref_no == original.contract_ref_no
      assert result.reg_date == original.reg_date
      assert result.start_date == original.start_date
      assert result.end_date == original.end_date
      assert result.active == original.active
      assert result.paid_invoices == original.paid_invoices
      assert result.unpaid_invoices == original.unpaid_invoices
      assert result.collection == original.collection
      assert result.last_invoice_status == original.last_invoice_status
      assert result.origin == original.origin
      assert result.trinity_id == original.trinity_id
      assert result.capway_id == original.capway_id
      assert result.raw_data == nil
    end

    test "round-trip with Swedish characters" do
      original = %CapwaySubscriber{
        name: "Björk Åström",
        id_number: "9001011234"
      }

      result =
        original
        |> CapwayCacheRepository.serialize_subscriber()
        |> CapwayCacheRepository.deserialize_subscriber()

      assert result.name == "Björk Åström"
    end
  end

  describe "bypass?/0" do
    test "returns true when CAPWAY_CACHE_BYPASS is 'true'" do
      System.put_env("CAPWAY_CACHE_BYPASS", "true")
      assert CapwayCacheRepository.bypass?() == true
      System.delete_env("CAPWAY_CACHE_BYPASS")
    end

    test "returns false when CAPWAY_CACHE_BYPASS is not set" do
      System.delete_env("CAPWAY_CACHE_BYPASS")
      assert CapwayCacheRepository.bypass?() == false
    end

    test "returns false when CAPWAY_CACHE_BYPASS is 'false'" do
      System.put_env("CAPWAY_CACHE_BYPASS", "false")
      assert CapwayCacheRepository.bypass?() == false
      System.delete_env("CAPWAY_CACHE_BYPASS")
    end

    test "returns false when CAPWAY_CACHE_BYPASS is empty string" do
      System.put_env("CAPWAY_CACHE_BYPASS", "")
      assert CapwayCacheRepository.bypass?() == false
      System.delete_env("CAPWAY_CACHE_BYPASS")
    end
  end

  describe "serialization for JSON encoding" do
    test "serialized subscriber can be encoded to JSON and decoded back" do
      subscriber = %CapwaySubscriber{
        customer_ref: "CR001",
        id_number: "1234567890",
        name: "Test User",
        active: "1"
      }

      serialized = CapwayCacheRepository.serialize_subscriber(subscriber)
      {:ok, json} = Jason.encode(serialized)
      {:ok, decoded} = Jason.decode(json)

      result = CapwayCacheRepository.deserialize_subscriber(decoded)
      assert result.customer_ref == "CR001"
      assert result.id_number == "1234567890"
    end

    test "list of serialized subscribers can be JSON round-tripped" do
      subscribers = [
        %CapwaySubscriber{id_number: "111", name: "Alice"},
        %CapwaySubscriber{id_number: "222", name: "Bob"},
        %CapwaySubscriber{id_number: "333", name: "Charlie"}
      ]

      serialized = Enum.map(subscribers, &CapwayCacheRepository.serialize_subscriber/1)
      {:ok, json} = Jason.encode(serialized)
      {:ok, decoded} = Jason.decode(json)

      results = Enum.map(decoded, &CapwayCacheRepository.deserialize_subscriber/1)
      assert length(results) == 3
      assert Enum.at(results, 0).id_number == "111"
      assert Enum.at(results, 1).name == "Bob"
      assert Enum.at(results, 2).id_number == "333"
    end
  end

  # Helpers

  defp build_subscribers(count) do
    Enum.map(1..count, fn i ->
      %CapwaySubscriber{
        customer_ref: "CR#{String.pad_leading(to_string(i), 4, "0")}",
        id_number: "ID#{String.pad_leading(to_string(i), 8, "0")}",
        name: "Subscriber #{i}",
        active: "1"
      }
    end)
  end
end
