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

    test "sets capway_sync_excluded to true for sinfrid subscription_type (atom)" do
      subscriber =
        build_trinity_subscriber([], %{
          subscription: %{
            id: 100,
            updated_at: ~N[2025-01-01 00:00:00],
            payment_method: "capway",
            end_date: nil,
            status: :active,
            subscription_type: :sinfrid
          }
        })

      canonical = Canonical.from_trinity(subscriber)

      assert canonical.subscription_type == :sinfrid
      assert canonical.capway_sync_excluded == true
    end

    test "sets capway_sync_excluded to true for sinfrid subscription_type (string)" do
      subscriber =
        build_trinity_subscriber([], %{
          subscription: %{
            id: 100,
            updated_at: ~N[2025-01-01 00:00:00],
            payment_method: "capway",
            end_date: nil,
            status: :active,
            subscription_type: "sinfrid"
          }
        })

      assert Canonical.from_trinity(subscriber).capway_sync_excluded == true
    end

    test "keeps capway_sync_excluded false for non-sinfrid subscription types" do
      subscriber =
        build_trinity_subscriber([], %{
          subscription: %{
            id: 100,
            updated_at: ~N[2025-01-01 00:00:00],
            payment_method: "capway",
            end_date: nil,
            status: :active,
            subscription_type: :locked
          }
        })

      assert Canonical.from_trinity(subscriber).capway_sync_excluded == false
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

  describe "from_capway/1 language_code" do
    test "always starts with language_code nil — populated later by FetchCapwayEmails" do
      capway_subscriber = %CapwaySync.Models.CapwaySubscriber{
        id_number: "199001011234",
        customer_ref: "1",
        contract_ref_no: "C-001",
        customer_id: "CID-001",
        active: "true"
      }

      assert Canonical.from_capway(capway_subscriber).language_code == nil
    end
  end

  describe "parse_customer_ref/1" do
    test "parses the v2 four-segment format into {wps_id, subscriber_id}" do
      assert Canonical.parse_customer_ref("v2-845714-61432-JSLGL") == {845_714, 61_432}
    end

    test "handles a future version prefix (v3, v10, …) the same way" do
      assert Canonical.parse_customer_ref("v3-1-2-abcde") == {1, 2}
      assert Canonical.parse_customer_ref("v10-1-2-abcde") == {1, 2}
    end

    test "accepts an uppercase version prefix (V2)" do
      assert Canonical.parse_customer_ref("V2-845714-61432-JSLGL") == {845_714, 61_432}
    end

    test "treats NO_TRIN_SUB sentinel as nil subscriber_id" do
      assert Canonical.parse_customer_ref("v2-845714-NO_TRIN_SUB-JSLGL") == {845_714, nil}
    end

    test "treats NO_WPS_ID sentinel as nil wps_id" do
      assert Canonical.parse_customer_ref("v2-NO_WPS_ID-61432-JSLGL") == {nil, 61_432}
    end

    test "preserves dashes inside the nanoid suffix" do
      assert Canonical.parse_customer_ref("v2-845714-61432-aB-x9") == {845_714, 61_432}
    end

    test "falls back to legacy plain-integer parsing" do
      assert Canonical.parse_customer_ref("61432") == {nil, 61_432}
    end

    test "returns {nil, nil} for nil or unparseable input" do
      assert Canonical.parse_customer_ref(nil) == {nil, nil}
      assert Canonical.parse_customer_ref("garbage") == {nil, nil}
    end
  end

  describe "from_capway/1 customer_ref parsing" do
    test "extracts trinity_subscriber_id and trinity_subscription_id from v2 customer_ref" do
      capway_subscriber = %CapwaySync.Models.CapwaySubscriber{
        id_number: "195803145217",
        customer_ref: "v2-845714-61432-JSLGL",
        contract_ref_no: "v2:1777396299:845714",
        customer_id: "297049",
        active: "true"
      }

      canonical = Canonical.from_capway(capway_subscriber)

      assert canonical.trinity_subscriber_id == 61_432
      assert canonical.trinity_subscription_id == 845_714
    end

    test "still works with legacy plain-integer customer_ref" do
      capway_subscriber = %CapwaySync.Models.CapwaySubscriber{
        id_number: "199001011234",
        customer_ref: "61432",
        contract_ref_no: "C-001",
        customer_id: "CID-001",
        active: "true"
      }

      canonical = Canonical.from_capway(capway_subscriber)

      assert canonical.trinity_subscriber_id == 61_432
      assert canonical.trinity_subscription_id == nil
    end

    test "leaves both ids nil when customer_ref is unparseable" do
      capway_subscriber = %CapwaySync.Models.CapwaySubscriber{
        id_number: "199001011234",
        customer_ref: "garbage",
        contract_ref_no: "C-001",
        customer_id: "CID-001",
        active: "true"
      }

      canonical = Canonical.from_capway(capway_subscriber)

      assert canonical.trinity_subscriber_id == nil
      assert canonical.trinity_subscription_id == nil
    end
  end
end
