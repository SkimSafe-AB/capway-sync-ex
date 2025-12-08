defmodule CapwaySync.Models.Subscribers.CanonicalTest do
  use ExUnit.Case, async: true
  alias CapwaySync.Models.Subscribers.Canonical
  alias CapwaySync.Models.CapwaySubscriber

  describe "from_trinity/1" do
    test "converts Trinity subscriber to canonical format" do
      trinity_subscriber = %{
        personal_number: "199001012345",
        subscription: %{
          id: 123,
          payment_method: "capway",
          status: :active,
          end_date: ~N[2024-12-31 23:59:59],
          subscription_type: "locked"
        },
        id: 456
      }

      result = Canonical.from_trinity(trinity_subscriber)

      assert %Canonical{
               id_number: "199001012345",
               trinity_id: 456,
               capway_id: nil,
               contract_ref: "123",
               payment_method: "capway",
               active: true,
               end_date: ~N[2024-12-31 23:59:59],
               origin: :trinity,
               subscription_type: "locked"
             } = result
    end

    test "handles inactive subscription" do
      trinity_subscriber = %{
        personal_number: "199001012345",
        subscription: %{
          id: 123,
          payment_method: "bank",
          status: :cancelled,
          end_date: nil,
          subscription_type: nil
        },
        id: 456
      }

      result = Canonical.from_trinity(trinity_subscriber)

      assert result.payment_method == "bank"
      assert result.active == false
      assert result.end_date == nil
      assert result.subscription_type == nil
    end
  end

  describe "from_capway/1" do
    test "converts Capway subscriber to canonical format" do
      capway_subscriber = %CapwaySubscriber{
        customer_ref: "123",
        id_number: "199001012345",
        contract_ref_no: "456",
        active: true,
        end_date: ~N[2024-12-31 23:59:59]
      }

      result = Canonical.from_capway(capway_subscriber)

      assert %Canonical{
               id_number: "199001012345",
               trinity_id: nil,
               capway_id: "123",
               contract_ref: "456",
               payment_method: nil,
               active: true,
               end_date: ~N[2024-12-31 23:59:59],
               origin: :capway
             } = result
    end

    test "handles inactive contract" do
      capway_subscriber = %CapwaySubscriber{
        customer_ref: "123",
        id_number: "199001012345",
        contract_ref_no: "456",
        active: false,
        end_date: nil
      }

      result = Canonical.from_capway(capway_subscriber)

      assert result.active == false
      assert result.payment_method == nil
    end
  end

  describe "from_trinity_list/1" do
    test "converts list of Trinity subscribers" do
      trinity_subscribers = [
        %{
          personal_number: "199001012345",
          subscription: %{id: 123, payment_method: "capway", status: :active, end_date: nil, subscription_type: "locked"},
          id: 456
        },
        %{
          personal_number: "199002023456",
          subscription: %{id: 124, payment_method: "bank", status: :cancelled, end_date: nil, subscription_type: nil},
          id: 457
        }
      ]

      result = Canonical.from_trinity_list(trinity_subscribers)

      assert length(result) == 2
      assert Enum.all?(result, &(&1.__struct__ == Canonical))
      assert Enum.all?(result, &(&1.origin == :trinity))

      first = Enum.at(result, 0)
      assert first.payment_method == "capway"
      assert first.active == true
      assert first.subscription_type == "locked"

      second = Enum.at(result, 1)
      assert second.payment_method == "bank"
      assert second.active == false
      assert second.subscription_type == nil
    end

    test "handles empty list" do
      result = Canonical.from_trinity_list([])
      assert result == []
    end
  end

  describe "from_capway_list/1" do
    test "converts list of Capway subscribers" do
      capway_subscribers = [
        %CapwaySubscriber{
          customer_ref: "123",
          id_number: "199001012345",
          contract_ref_no: "456",
          active: true,
          end_date: nil
        },
        %CapwaySubscriber{
          customer_ref: "124",
          id_number: "199002023456",
          contract_ref_no: "457",
          active: false,
          end_date: nil
        }
      ]

      result = Canonical.from_capway_list(capway_subscribers)

      assert length(result) == 2
      assert Enum.all?(result, &(&1.__struct__ == Canonical))
      assert Enum.all?(result, &(&1.origin == :capway))
      assert Enum.all?(result, &(&1.payment_method == nil))
    end

    test "handles empty list" do
      result = Canonical.from_capway_list([])
      assert result == []
    end
  end
end