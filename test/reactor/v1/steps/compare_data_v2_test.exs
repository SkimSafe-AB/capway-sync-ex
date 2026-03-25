defmodule CapwaySync.Reactor.V1.Steps.CompareDataV2Test do
  use ExUnit.Case, async: true

  alias CapwaySync.Reactor.V1.Steps.CompareDataV2
  alias CapwaySync.Models.Subscribers.Canonical

  defp build_capway_sub(attrs) do
    Map.merge(
      %Canonical{
        national_id: "199001011234",
        trinity_subscriber_id: 1,
        trinity_subscription_id: 100,
        capway_contract_ref: "C-001",
        capway_customer_id: "CID-001",
        capway_active_status: true,
        origin: :capway,
        collection: 3,
        last_invoice_status: "Invoice",
        payment_method: nil,
        trinity_status: nil,
        subscription_type: nil
      },
      attrs
    )
  end

  defp build_trinity_sub(attrs) do
    Map.merge(
      %Canonical{
        national_id: "199001011234",
        trinity_subscriber_id: 1,
        trinity_subscription_id: 100,
        origin: :trinity,
        payment_method: "capway",
        trinity_status: :active,
        subscription_type: :standard,
        capway_active_status: nil,
        capway_customer_id: nil,
        collection: nil,
        last_invoice_status: nil
      },
      attrs
    )
  end

  describe "get_accounts_to_suspend_or_cancel/3" do
    test "cancels subscriber with collection >= 2 and unpaid invoice" do
      capway_sub = build_capway_sub(%{collection: 3, last_invoice_status: "Invoice"})
      trinity_sub = build_trinity_sub(%{})

      capway_data = %{"C-001" => capway_sub}
      trinity_data = %{1 => trinity_sub}
      trinity_map_set = %{active_national_ids: MapSet.new(["199001011234"])}

      {suspend, cancel} =
        CompareDataV2.get_accounts_to_suspend_or_cancel(capway_data, trinity_data, trinity_map_set)

      assert map_size(cancel) == 1
      assert map_size(suspend) == 0
      assert Map.has_key?(cancel, "C-001")
    end

    test "excludes subscriber with last_invoice_status Paid from cancel" do
      capway_sub = build_capway_sub(%{collection: 3, last_invoice_status: "Paid"})
      trinity_sub = build_trinity_sub(%{})

      capway_data = %{"C-001" => capway_sub}
      trinity_data = %{1 => trinity_sub}
      trinity_map_set = %{active_national_ids: MapSet.new(["199001011234"])}

      {suspend, cancel} =
        CompareDataV2.get_accounts_to_suspend_or_cancel(capway_data, trinity_data, trinity_map_set)

      assert map_size(cancel) == 0
      assert map_size(suspend) == 0
    end

    test "suspends locked subscriber even with Paid invoice" do
      capway_sub = build_capway_sub(%{collection: 3, last_invoice_status: "Paid"})
      trinity_sub = build_trinity_sub(%{subscription_type: :locked})

      capway_data = %{"C-001" => capway_sub}
      trinity_data = %{1 => trinity_sub}
      trinity_map_set = %{active_national_ids: MapSet.new(["199001011234"])}

      {suspend, cancel} =
        CompareDataV2.get_accounts_to_suspend_or_cancel(capway_data, trinity_data, trinity_map_set)

      assert map_size(suspend) == 1
      assert map_size(cancel) == 0
      assert Map.has_key?(suspend, "C-001")
    end

    test "excludes pending_cancel subscriber from cancel" do
      capway_sub = build_capway_sub(%{collection: 3, last_invoice_status: "Invoice"})
      trinity_sub = build_trinity_sub(%{trinity_status: :pending_cancel})

      capway_data = %{"C-001" => capway_sub}
      trinity_data = %{1 => trinity_sub}
      trinity_map_set = %{active_national_ids: MapSet.new(["199001011234"])}

      {suspend, cancel} =
        CompareDataV2.get_accounts_to_suspend_or_cancel(capway_data, trinity_data, trinity_map_set)

      assert map_size(cancel) == 0
      assert map_size(suspend) == 0
    end

    test "excludes non-capway payment method from cancel" do
      capway_sub = build_capway_sub(%{collection: 3, last_invoice_status: "Reminder"})
      trinity_sub = build_trinity_sub(%{payment_method: "invoice"})

      capway_data = %{"C-001" => capway_sub}
      trinity_data = %{1 => trinity_sub}
      trinity_map_set = %{active_national_ids: MapSet.new(["199001011234"])}

      {suspend, cancel} =
        CompareDataV2.get_accounts_to_suspend_or_cancel(capway_data, trinity_data, trinity_map_set)

      assert map_size(cancel) == 0
      assert map_size(suspend) == 0
    end

    test "cancels subscriber with Collection Agency status" do
      capway_sub = build_capway_sub(%{collection: 4, last_invoice_status: "Collection Agency"})
      trinity_sub = build_trinity_sub(%{})

      capway_data = %{"C-001" => capway_sub}
      trinity_data = %{1 => trinity_sub}
      trinity_map_set = %{active_national_ids: MapSet.new(["199001011234"])}

      {suspend, cancel} =
        CompareDataV2.get_accounts_to_suspend_or_cancel(capway_data, trinity_data, trinity_map_set)

      assert map_size(cancel) == 1
      assert map_size(suspend) == 0
    end

    test "cancels subscriber with Reminder status" do
      capway_sub = build_capway_sub(%{collection: 2, last_invoice_status: "Reminder"})
      trinity_sub = build_trinity_sub(%{})

      capway_data = %{"C-001" => capway_sub}
      trinity_data = %{1 => trinity_sub}
      trinity_map_set = %{active_national_ids: MapSet.new(["199001011234"])}

      {suspend, cancel} =
        CompareDataV2.get_accounts_to_suspend_or_cancel(capway_data, trinity_data, trinity_map_set)

      assert map_size(cancel) == 1
      assert map_size(suspend) == 0
    end

    test "two active contracts for same customer produce two separate action items" do
      capway_sub_1 =
        build_capway_sub(%{
          capway_contract_ref: "C-001",
          collection: 3,
          last_invoice_status: "Invoice"
        })

      capway_sub_2 =
        build_capway_sub(%{
          capway_contract_ref: "C-002",
          collection: 4,
          last_invoice_status: "Reminder"
        })

      trinity_sub = build_trinity_sub(%{})

      capway_data = %{"C-001" => capway_sub_1, "C-002" => capway_sub_2}
      trinity_data = %{1 => trinity_sub}
      trinity_map_set = %{active_national_ids: MapSet.new(["199001011234"])}

      {suspend, cancel} =
        CompareDataV2.get_accounts_to_suspend_or_cancel(capway_data, trinity_data, trinity_map_set)

      assert map_size(cancel) == 2
      assert map_size(suspend) == 0
      assert Map.has_key?(cancel, "C-001")
      assert Map.has_key?(cancel, "C-002")
    end

    test "two locked contracts produce two separate suspend action items" do
      capway_sub_1 =
        build_capway_sub(%{
          capway_contract_ref: "C-001",
          collection: 3
        })

      capway_sub_2 =
        build_capway_sub(%{
          capway_contract_ref: "C-002",
          collection: 2
        })

      trinity_sub = build_trinity_sub(%{subscription_type: :locked})

      capway_data = %{"C-001" => capway_sub_1, "C-002" => capway_sub_2}
      trinity_data = %{1 => trinity_sub}
      trinity_map_set = %{active_national_ids: MapSet.new(["199001011234"])}

      {suspend, cancel} =
        CompareDataV2.get_accounts_to_suspend_or_cancel(capway_data, trinity_data, trinity_map_set)

      assert map_size(suspend) == 2
      assert map_size(cancel) == 0
      assert Map.has_key?(suspend, "C-001")
      assert Map.has_key?(suspend, "C-002")
    end

    test "action item includes all identifying fields" do
      capway_sub =
        build_capway_sub(%{
          collection: 3,
          capway_contract_ref: "C-999",
          capway_customer_id: "CID-999",
          trinity_subscription_id: 555
        })

      trinity_sub = build_trinity_sub(%{subscription_type: :locked})

      capway_data = %{"C-999" => capway_sub}
      trinity_data = %{1 => trinity_sub}
      trinity_map_set = %{active_national_ids: MapSet.new(["199001011234"])}

      {suspend, _cancel} =
        CompareDataV2.get_accounts_to_suspend_or_cancel(capway_data, trinity_data, trinity_map_set)

      action_item = Map.get(suspend, "C-999")
      assert action_item.capway_contract_ref == "C-999"
      assert action_item.capway_customer_id == "CID-999"
      assert action_item.trinity_subscriber_id == 1
      assert action_item.trinity_subscription_id == 555
      assert action_item.national_id == "199001011234"
    end

    test "excludes already suspended subscriber" do
      capway_sub = build_capway_sub(%{collection: 3, last_invoice_status: "Invoice"})
      trinity_sub = build_trinity_sub(%{trinity_status: :suspended})

      capway_data = %{"C-001" => capway_sub}
      trinity_data = %{1 => trinity_sub}
      trinity_map_set = %{active_national_ids: MapSet.new(["199001011234"])}

      {suspend, cancel} =
        CompareDataV2.get_accounts_to_suspend_or_cancel(capway_data, trinity_data, trinity_map_set)

      assert map_size(suspend) == 0
      assert map_size(cancel) == 0
    end

    test "excludes already cancelled subscriber" do
      capway_sub = build_capway_sub(%{collection: 3, last_invoice_status: "Invoice"})
      trinity_sub = build_trinity_sub(%{trinity_status: :cancelled})

      capway_data = %{"C-001" => capway_sub}
      trinity_data = %{1 => trinity_sub}
      trinity_map_set = %{active_national_ids: MapSet.new(["199001011234"])}

      {suspend, cancel} =
        CompareDataV2.get_accounts_to_suspend_or_cancel(capway_data, trinity_data, trinity_map_set)

      assert map_size(suspend) == 0
      assert map_size(cancel) == 0
    end

    test "excludes suspended subscriber even with locked subscription" do
      capway_sub = build_capway_sub(%{collection: 3})
      trinity_sub = build_trinity_sub(%{subscription_type: :locked, trinity_status: :suspended})

      capway_data = %{"C-001" => capway_sub}
      trinity_data = %{1 => trinity_sub}
      trinity_map_set = %{active_national_ids: MapSet.new(["199001011234"])}

      {suspend, cancel} =
        CompareDataV2.get_accounts_to_suspend_or_cancel(capway_data, trinity_data, trinity_map_set)

      assert map_size(suspend) == 0
      assert map_size(cancel) == 0
    end
  end

  describe "get_contracts_to_update/2" do
    test "marks contract for update when national_id differs and trinity pnr is valid" do
      capway_sub = build_capway_sub(%{national_id: "198507099805", trinity_subscriber_id: 1, collection: 0})
      trinity_sub = build_trinity_sub(%{national_id: "196403273813"})

      capway_data = %{"C-001" => capway_sub}
      trinity_data = %{1 => trinity_sub}

      result = CompareDataV2.get_contracts_to_update(capway_data, trinity_data)

      assert map_size(result) == 1
      assert Map.has_key?(result, "C-001")
    end

    test "enriches trinity_subscription_id from subscriber_to_subscription_ids map" do
      capway_sub =
        build_capway_sub(%{
          national_id: "198507099805",
          trinity_subscriber_id: 1,
          trinity_subscription_id: nil,
          collection: 0
        })

      trinity_sub = build_trinity_sub(%{national_id: "196403273813", trinity_subscription_id: 200})

      capway_data = %{"C-001" => capway_sub}
      trinity_data = %{1 => trinity_sub}
      sub_to_sub_ids = %{1 => 200}

      result = CompareDataV2.get_contracts_to_update(capway_data, trinity_data, sub_to_sub_ids)

      action_item = Map.get(result, "C-001")
      assert action_item.trinity_subscription_id == 200
    end

    test "does not mark contract for update when national_ids match" do
      capway_sub = build_capway_sub(%{national_id: "196403273813", trinity_subscriber_id: 1})
      trinity_sub = build_trinity_sub(%{national_id: "196403273813"})

      capway_data = %{"C-001" => capway_sub}
      trinity_data = %{1 => trinity_sub}

      result = CompareDataV2.get_contracts_to_update(capway_data, trinity_data)

      assert map_size(result) == 0
    end

    test "does not mark contract for update when trinity national_id is invalid personnummer" do
      capway_sub = build_capway_sub(%{national_id: "198507099805", trinity_subscriber_id: 1})
      trinity_sub = build_trinity_sub(%{national_id: "invalid_pnr"})

      capway_data = %{"C-001" => capway_sub}
      trinity_data = %{1 => trinity_sub}

      result = CompareDataV2.get_contracts_to_update(capway_data, trinity_data)

      assert map_size(result) == 0
    end

    test "does not mark contract for update when trinity national_id is nil" do
      capway_sub = build_capway_sub(%{national_id: "196403273813", trinity_subscriber_id: 1})
      trinity_sub = build_trinity_sub(%{national_id: nil})

      capway_data = %{"C-001" => capway_sub}
      trinity_data = %{1 => trinity_sub}

      result = CompareDataV2.get_contracts_to_update(capway_data, trinity_data)

      assert map_size(result) == 0
    end

    test "does not mark contract for update when collection is >= 2" do
      capway_sub =
        build_capway_sub(%{national_id: "198507099805", trinity_subscriber_id: 1, collection: 2})

      trinity_sub = build_trinity_sub(%{national_id: "196403273813"})

      capway_data = %{"C-001" => capway_sub}
      trinity_data = %{1 => trinity_sub}

      result = CompareDataV2.get_contracts_to_update(capway_data, trinity_data)

      assert map_size(result) == 0
    end

    test "marks contract for update when collection is below 2" do
      capway_sub =
        build_capway_sub(%{national_id: "198507099805", trinity_subscriber_id: 1, collection: 1})

      trinity_sub = build_trinity_sub(%{national_id: "196403273813"})

      capway_data = %{"C-001" => capway_sub}
      trinity_data = %{1 => trinity_sub}

      result = CompareDataV2.get_contracts_to_update(capway_data, trinity_data)

      assert map_size(result) == 1
      assert Map.has_key?(result, "C-001")
    end

    test "does not match when capway trinity_subscriber_id is nil" do
      capway_sub =
        build_capway_sub(%{
          national_id: "196403273813",
          trinity_subscriber_id: nil,
          capway_contract_ref: "C-001"
        })

      trinity_sub = build_trinity_sub(%{national_id: "196403273813"})

      capway_data = %{"C-001" => capway_sub}
      trinity_data = %{1 => trinity_sub}

      result = CompareDataV2.get_contracts_to_update(capway_data, trinity_data)

      # No match because Map.has_key?(trinity_data, nil) is false
      assert map_size(result) == 0
    end
  end

  describe "run/3 update/cancel exclusion" do
    test "excludes update contracts that also appear in cancel contracts" do
      # Contract C-001: exists in Trinity (update candidate due to national_id mismatch)
      capway_sub_update =
        build_capway_sub(%{
          capway_contract_ref: "C-001",
          trinity_subscriber_id: 1,
          national_id: "198507099805",
          collection: 0
        })

      # Contract C-002: no Trinity match (cancel candidate)
      capway_sub_cancel =
        build_capway_sub(%{
          capway_contract_ref: "C-002",
          trinity_subscriber_id: 9999,
          national_id: "199505051234"
        })

      trinity_sub = build_trinity_sub(%{national_id: "196403273813", trinity_subscriber_id: 1})

      args = %{
        data: %{
          capway: %{
            active_subscribers: %{
              "C-001" => capway_sub_update,
              "C-002" => capway_sub_cancel
            },
            above_collector_threshold: %{},
            map_sets: %{
              active_trinity_ids: MapSet.new([1, 9999]),
              active_national_ids: MapSet.new(["198507099805", "199505051234"])
            }
          },
          trinity: %{
            active_subscribers: %{1 => trinity_sub},
            locked_subscribers: %{},
            map_sets: %{
              subscriber_to_subscription_ids: %{},
              all_national_ids: MapSet.new(["196403273813"]),
              all_subscriber_ids: MapSet.new([1]),
              active_national_ids: MapSet.new(["196403273813"]),
              recently_cancelled_subscriber_ids: MapSet.new(),
              recently_cancelled_national_ids: MapSet.new()
            }
          }
        }
      }

      {:ok, result} = CompareDataV2.run(args, %{}, [])

      # C-001 should be in update (not in cancel)
      assert Map.has_key?(result.actions.capway.update_contracts, "C-001")
      refute Map.has_key?(result.actions.capway.cancel_contracts, "C-001")

      # C-002 should be in cancel (not in update)
      assert Map.has_key?(result.actions.capway.cancel_contracts, "C-002")
      refute Map.has_key?(result.actions.capway.update_contracts, "C-002")
    end

    test "contract with collection >= 2 excluded from update does not end up in cancel" do
      # Contract with collection 2, exists in Trinity with mismatched national_id
      # Should be excluded from update (collection >= 2) but NOT added to cancel
      capway_sub =
        build_capway_sub(%{
          capway_contract_ref: "C-collect",
          trinity_subscriber_id: 1,
          national_id: "198507099805",
          collection: 2
        })

      trinity_sub = build_trinity_sub(%{national_id: "196403273813", trinity_subscriber_id: 1})

      args = %{
        data: %{
          capway: %{
            active_subscribers: %{"C-collect" => capway_sub},
            above_collector_threshold: %{},
            map_sets: %{
              active_trinity_ids: MapSet.new([1]),
              active_national_ids: MapSet.new(["198507099805"])
            }
          },
          trinity: %{
            active_subscribers: %{1 => trinity_sub},
            locked_subscribers: %{},
            map_sets: %{
              subscriber_to_subscription_ids: %{},
              all_national_ids: MapSet.new(["196403273813"]),
              all_subscriber_ids: MapSet.new([1]),
              active_national_ids: MapSet.new(["196403273813"]),
              recently_cancelled_subscriber_ids: MapSet.new(),
              recently_cancelled_national_ids: MapSet.new()
            }
          }
        }
      }

      {:ok, result} = CompareDataV2.run(args, %{}, [])

      refute Map.has_key?(result.actions.capway.update_contracts, "C-collect")
      refute Map.has_key?(result.actions.capway.cancel_contracts, "C-collect")
    end
  end

  describe "get_contracts_to_create/2" do
    test "does not create contract for pending_cancel subscriber" do
      # A pending_cancel subscriber should never be in active_subscribers
      # (filtered out by Helper.group), but verify create logic itself
      # by confirming the full run/3 flow excludes it
      pending_cancel_sub =
        build_trinity_sub(%{
          trinity_status: :pending_cancel,
          trinity_subscriber_id: 42,
          national_id: "196403273813",
          trinity_subscription_updated_at: ~N[2025-01-01 00:00:00]
        })

      # Simulate: pending_cancel sub should NOT be in active_subscribers
      # but IS in all_national_ids / all_subscriber_ids
      args = %{
        data: %{
          capway: %{
            active_subscribers: %{},
            above_collector_threshold: %{},
            map_sets: %{
              active_trinity_ids: MapSet.new(),
              active_national_ids: MapSet.new()
            }
          },
          trinity: %{
            active_subscribers: %{},
            locked_subscribers: %{},
            map_sets: %{
              subscriber_to_subscription_ids: %{},
              all_national_ids: MapSet.new(["196403273813"]),
              all_subscriber_ids: MapSet.new([42]),
              active_national_ids: MapSet.new(),
              recently_cancelled_subscriber_ids: MapSet.new(),
              recently_cancelled_national_ids: MapSet.new()
            }
          }
        }
      }

      {:ok, result} = CompareDataV2.run(args, %{}, [])

      # No create action should be generated
      assert map_size(result.actions.capway.create_contracts) == 0
    end

    test "creates contract for active subscriber missing in Capway" do
      active_sub =
        build_trinity_sub(%{
          trinity_subscriber_id: 1,
          national_id: "196403273813",
          trinity_subscription_updated_at: ~N[2025-01-01 00:00:00]
        })

      args = %{
        data: %{
          capway: %{
            active_subscribers: %{},
            above_collector_threshold: %{},
            map_sets: %{
              active_trinity_ids: MapSet.new(),
              active_national_ids: MapSet.new()
            }
          },
          trinity: %{
            active_subscribers: %{1 => active_sub},
            locked_subscribers: %{},
            map_sets: %{
              subscriber_to_subscription_ids: %{},
              all_national_ids: MapSet.new(["196403273813"]),
              all_subscriber_ids: MapSet.new([1]),
              active_national_ids: MapSet.new(["196403273813"]),
              recently_cancelled_subscriber_ids: MapSet.new(),
              recently_cancelled_national_ids: MapSet.new()
            }
          }
        }
      }

      {:ok, result} = CompareDataV2.run(args, %{}, [])

      assert map_size(result.actions.capway.create_contracts) == 1
      assert Map.has_key?(result.actions.capway.create_contracts, 1)
    end
  end

  describe "get_contracts_to_cancel/5" do
    test "cancels contract with no matching trinity_subscriber_id" do
      capway_sub =
        build_capway_sub(%{
          trinity_subscriber_id: 9999,
          capway_contract_ref: "C-orphan"
        })

      trinity_sub = build_trinity_sub(%{})

      capway_data = %{"C-orphan" => capway_sub}
      trinity_data = %{1 => trinity_sub}

      result = CompareDataV2.get_contracts_to_cancel(capway_data, trinity_data)

      assert map_size(result) == 1
      assert Map.has_key?(result, "C-orphan")
    end

    test "enriches trinity_subscription_id from subscriber_to_subscription_ids map" do
      capway_sub =
        build_capway_sub(%{
          trinity_subscriber_id: 9999,
          trinity_subscription_id: nil,
          capway_contract_ref: "C-orphan"
        })

      trinity_sub = build_trinity_sub(%{})

      capway_data = %{"C-orphan" => capway_sub}
      trinity_data = %{1 => trinity_sub}
      sub_to_sub_ids = %{9999 => 500}

      result = CompareDataV2.get_contracts_to_cancel(capway_data, trinity_data, sub_to_sub_ids)

      action_item = Map.get(result, "C-orphan")
      assert action_item.trinity_subscription_id == 500
    end

    test "does not cancel contract when matched by trinity_subscriber_id" do
      capway_sub = build_capway_sub(%{trinity_subscriber_id: 1, capway_contract_ref: "C-001"})
      trinity_sub = build_trinity_sub(%{})

      capway_data = %{"C-001" => capway_sub}
      trinity_data = %{1 => trinity_sub}

      result = CompareDataV2.get_contracts_to_cancel(capway_data, trinity_data)

      assert map_size(result) == 0
    end

    test "cancels contract when neither trinity_subscriber_id nor national_id match" do
      capway_sub =
        build_capway_sub(%{
          trinity_subscriber_id: 9999,
          national_id: "199001011234",
          capway_contract_ref: "C-001"
        })

      trinity_sub = build_trinity_sub(%{})

      capway_data = %{"C-001" => capway_sub}
      trinity_data = %{1 => trinity_sub}
      trinity_national_ids = MapSet.new(["196403273813"])

      result = CompareDataV2.get_contracts_to_cancel(capway_data, trinity_data, %{}, trinity_national_ids)

      assert map_size(result) == 1
    end

    test "does not cancel contract without customer_ref when national_id matches Trinity" do
      capway_sub =
        build_capway_sub(%{
          trinity_subscriber_id: nil,
          national_id: "199001011234",
          capway_contract_ref: "C-sinfrid"
        })

      capway_data = %{"C-sinfrid" => capway_sub}
      trinity_data = %{1 => build_trinity_sub(%{national_id: "199001011234"})}
      trinity_national_ids = MapSet.new(["199001011234"])

      result = CompareDataV2.get_contracts_to_cancel(capway_data, trinity_data, %{}, trinity_national_ids)

      assert map_size(result) == 0
    end

    test "does not cancel contract when Trinity subscriber exists but is too recent" do
      capway_sub =
        build_capway_sub(%{
          trinity_subscriber_id: 1,
          national_id: "199001011234",
          capway_contract_ref: "C-new"
        })

      # Trinity subscriber exists but was filtered out of active_subscribers
      # (e.g. created yesterday, capway metadata too recent)
      # So trinity_data is empty, but all_national_ids still includes it
      capway_data = %{"C-new" => capway_sub}
      trinity_data = %{}
      all_national_ids = MapSet.new(["199001011234"])

      result = CompareDataV2.get_contracts_to_cancel(capway_data, trinity_data, %{}, all_national_ids)

      assert map_size(result) == 0
    end

    test "cancels contract without customer_ref when national_id not in Trinity" do
      capway_sub =
        build_capway_sub(%{
          trinity_subscriber_id: nil,
          national_id: "199001011234",
          capway_contract_ref: "C-sinfrid"
        })

      capway_data = %{"C-sinfrid" => capway_sub}
      trinity_data = %{}
      trinity_national_ids = MapSet.new()

      result = CompareDataV2.get_contracts_to_cancel(capway_data, trinity_data, %{}, trinity_national_ids)

      assert map_size(result) == 1
      assert Map.has_key?(result, "C-sinfrid")
    end

    test "does not cancel contract when subscriber was recently cancelled in capway" do
      capway_sub =
        build_capway_sub(%{
          trinity_subscriber_id: 1,
          national_id: "199001011234",
          capway_contract_ref: "C-recent-cancel"
        })

      capway_data = %{"C-recent-cancel" => capway_sub}
      trinity_data = %{}
      all_national_ids = MapSet.new()
      all_subscriber_ids = MapSet.new()
      recently_cancelled_subscriber_ids = MapSet.new([1])
      recently_cancelled_national_ids = MapSet.new(["199001011234"])

      result =
        CompareDataV2.get_contracts_to_cancel(
          capway_data,
          trinity_data,
          %{},
          all_national_ids,
          all_subscriber_ids,
          recently_cancelled_subscriber_ids,
          recently_cancelled_national_ids
        )

      assert map_size(result) == 0
    end

    test "cancels contract when capway cancellation is older than 2 days" do
      capway_sub =
        build_capway_sub(%{
          trinity_subscriber_id: 1,
          national_id: "199001011234",
          capway_contract_ref: "C-old-cancel"
        })

      capway_data = %{"C-old-cancel" => capway_sub}
      trinity_data = %{}
      all_national_ids = MapSet.new()
      all_subscriber_ids = MapSet.new()
      # Not in recently cancelled sets (older than 2 days)
      recently_cancelled_subscriber_ids = MapSet.new()
      recently_cancelled_national_ids = MapSet.new()

      result =
        CompareDataV2.get_contracts_to_cancel(
          capway_data,
          trinity_data,
          %{},
          all_national_ids,
          all_subscriber_ids,
          recently_cancelled_subscriber_ids,
          recently_cancelled_national_ids
        )

      assert map_size(result) == 1
      assert Map.has_key?(result, "C-old-cancel")
    end

    test "does not cancel contract when subscriber is pending_cancel" do
      capway_sub =
        build_capway_sub(%{
          trinity_subscriber_id: 1,
          national_id: "199001011234",
          capway_contract_ref: "C-pending-cancel"
        })

      capway_data = %{"C-pending-cancel" => capway_sub}
      # pending_cancel subscriber not in active_subscribers
      trinity_data = %{}
      # But still in all_national_ids and all_subscriber_ids (not fully cancelled yet)
      all_national_ids = MapSet.new(["199001011234"])
      all_subscriber_ids = MapSet.new([1])

      result =
        CompareDataV2.get_contracts_to_cancel(
          capway_data,
          trinity_data,
          %{},
          all_national_ids,
          all_subscriber_ids
        )

      assert map_size(result) == 0
    end

    test "does not cancel contract when subscriber is pending with no personal_number" do
      # Capway contract has customer_ref pointing to a pending Trinity subscriber
      # that has no personal_number yet (activated: false)
      capway_sub =
        build_capway_sub(%{
          trinity_subscriber_id: 59882,
          national_id: nil,
          capway_contract_ref: "C-pending"
        })

      capway_data = %{"C-pending" => capway_sub}
      # Subscriber not in active_subscribers (pending status)
      trinity_data = %{}
      # No national_id to match
      all_national_ids = MapSet.new()
      # But subscriber ID exists in all_subscriber_ids
      all_subscriber_ids = MapSet.new([59882])

      result =
        CompareDataV2.get_contracts_to_cancel(
          capway_data,
          trinity_data,
          %{},
          all_national_ids,
          all_subscriber_ids
        )

      assert map_size(result) == 0
    end
  end

end
