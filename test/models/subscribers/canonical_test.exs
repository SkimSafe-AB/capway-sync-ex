defmodule CapwaySync.Models.Subscribers.CanonicalTest do
  use ExUnit.Case, async: true
  alias CapwaySync.Models.Subscribers.Canonical

  defp build_trinity_subscriber(metadata \\ [], extra \\ %{}) do
    Map.merge(
      %{
        personal_number: "199001011234",
        id: 1,
        subscription: %{
          id: 100,
          updated_at: ~N[2025-01-01 00:00:00],
          payment_method: "capway",
          end_date: nil,
          status: :active,
          subscription_type: :standard
        },
        metadata: metadata
      },
      extra
    )
  end

  describe "from_trinity/1 capway_sync_excluded" do
    test "sets capway_sync_excluded to true when metadata value is 'true'" do
      subscriber =
        build_trinity_subscriber([
          %{key: "capway_sync_excluded", value: "true"}
        ])

      canonical = Canonical.from_trinity(subscriber)

      assert canonical.capway_sync_excluded == true
    end

    test "sets capway_sync_excluded to false when metadata value is 'false'" do
      subscriber =
        build_trinity_subscriber([
          %{key: "capway_sync_excluded", value: "false"}
        ])

      canonical = Canonical.from_trinity(subscriber)

      assert canonical.capway_sync_excluded == false
    end

    test "sets capway_sync_excluded to false when metadata key is absent" do
      subscriber = build_trinity_subscriber([])

      canonical = Canonical.from_trinity(subscriber)

      assert canonical.capway_sync_excluded == false
    end

    test "sets capway_sync_excluded to false when metadata value is nil" do
      subscriber =
        build_trinity_subscriber([
          %{key: "capway_sync_excluded", value: nil}
        ])

      canonical = Canonical.from_trinity(subscriber)

      assert canonical.capway_sync_excluded == false
    end
  end

  describe "from_trinity/1 email" do
    test "carries email through to canonical" do
      subscriber = build_trinity_subscriber([], %{email: "alice@example.com"})
      assert Canonical.from_trinity(subscriber).email == "alice@example.com"
    end

    test "leaves email nil when subscriber has no email field" do
      subscriber = build_trinity_subscriber()
      assert Canonical.from_trinity(subscriber).email == nil
    end
  end

  describe "from_capway/1 email" do
    test "always starts with email nil — populated later by FetchCapwayEmails" do
      capway_subscriber = %CapwaySync.Models.CapwaySubscriber{
        id_number: "199001011234",
        customer_ref: "1",
        contract_ref_no: "C-001",
        customer_id: "CID-001",
        active: "true"
      }

      assert Canonical.from_capway(capway_subscriber).email == nil
    end
  end
end
