defmodule CapwaySync.Reactor.V1.Steps.CompareDataV2Test do
  use ExUnit.Case, async: true

  alias CapwaySync.Reactor.V1.Steps.CompareDataV2
  alias CapwaySync.Models.Subscribers.Canonical

  # Default market in the test env is :se, whose expected language/currency are
  # "sv"/"SEK". Seed the Capway side with the correct values so tests that aren't
  # about language/currency don't incidentally flag a mismatch (a blank/wrong
  # value counts as an update). Field-specific tests override these.
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
        subscription_type: nil,
        language_code: "sv",
        currency_code: "SEK"
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

  describe "get_customers_to_update/2" do
    test "marks customer for update when national_id differs and trinity pnr is valid" do
      capway_sub = build_capway_sub(%{national_id: "198507099805", trinity_subscriber_id: 1, collection: 0})
      trinity_sub = build_trinity_sub(%{national_id: "196403273813"})

      capway_data = %{"C-001" => capway_sub}
      trinity_data = %{1 => trinity_sub}

      result = CompareDataV2.get_customers_to_update(capway_data, trinity_data)

      assert map_size(result) == 1
      assert Map.has_key?(result, "C-001")
      action_item = Map.get(result, "C-001")
      assert action_item.action == :capway_update_customer
      assert action_item.sub_action == [:update_nin]
      assert action_item.comment == "National ID mismatch"
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

      result = CompareDataV2.get_customers_to_update(capway_data, trinity_data, sub_to_sub_ids)

      action_item = Map.get(result, "C-001")
      assert action_item.trinity_subscription_id == 200
    end

    test "does not mark customer for update when national_ids match" do
      capway_sub = build_capway_sub(%{national_id: "196403273813", trinity_subscriber_id: 1})
      trinity_sub = build_trinity_sub(%{national_id: "196403273813"})

      capway_data = %{"C-001" => capway_sub}
      trinity_data = %{1 => trinity_sub}

      result = CompareDataV2.get_customers_to_update(capway_data, trinity_data)

      assert map_size(result) == 0
    end

    test "does not mark customer for update when trinity national_id is invalid personnummer" do
      capway_sub = build_capway_sub(%{national_id: "198507099805", trinity_subscriber_id: 1})
      trinity_sub = build_trinity_sub(%{national_id: "invalid_pnr"})

      capway_data = %{"C-001" => capway_sub}
      trinity_data = %{1 => trinity_sub}

      result = CompareDataV2.get_customers_to_update(capway_data, trinity_data)

      assert map_size(result) == 0
    end

    test "does not mark customer for update when trinity national_id is nil" do
      capway_sub = build_capway_sub(%{national_id: "196403273813", trinity_subscriber_id: 1})
      trinity_sub = build_trinity_sub(%{national_id: nil})

      capway_data = %{"C-001" => capway_sub}
      trinity_data = %{1 => trinity_sub}

      result = CompareDataV2.get_customers_to_update(capway_data, trinity_data)

      assert map_size(result) == 0
    end

    test "does not mark customer for update when collection is >= 2" do
      capway_sub =
        build_capway_sub(%{national_id: "198507099805", trinity_subscriber_id: 1, collection: 2})

      trinity_sub = build_trinity_sub(%{national_id: "196403273813"})

      capway_data = %{"C-001" => capway_sub}
      trinity_data = %{1 => trinity_sub}

      result = CompareDataV2.get_customers_to_update(capway_data, trinity_data)

      assert map_size(result) == 0
    end

    test "marks customer for update when collection is below 2" do
      capway_sub =
        build_capway_sub(%{national_id: "198507099805", trinity_subscriber_id: 1, collection: 1})

      trinity_sub = build_trinity_sub(%{national_id: "196403273813"})

      capway_data = %{"C-001" => capway_sub}
      trinity_data = %{1 => trinity_sub}

      result = CompareDataV2.get_customers_to_update(capway_data, trinity_data)

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

      result = CompareDataV2.get_customers_to_update(capway_data, trinity_data)

      # No match because Map.has_key?(trinity_data, nil) is false
      assert map_size(result) == 0
    end

    test "does not flag mismatch when national_ids differ only by trailing whitespace" do
      capway_sub = build_capway_sub(%{national_id: "196403273813", trinity_subscriber_id: 1})
      trinity_sub = build_trinity_sub(%{national_id: "196403273813 "})

      capway_data = %{"C-001" => capway_sub}
      trinity_data = %{1 => trinity_sub}

      result = CompareDataV2.get_customers_to_update(capway_data, trinity_data)

      assert map_size(result) == 0
    end

    test "does not flag mismatch when national_ids differ only by an internal space" do
      capway_sub = build_capway_sub(%{national_id: "196403273813", trinity_subscriber_id: 1})
      trinity_sub = build_trinity_sub(%{national_id: "196403 273813"})

      capway_data = %{"C-001" => capway_sub}
      trinity_data = %{1 => trinity_sub}

      result = CompareDataV2.get_customers_to_update(capway_data, trinity_data)

      assert map_size(result) == 0
    end

    test "does not flag mismatch when capway side carries leading/trailing whitespace" do
      capway_sub = build_capway_sub(%{national_id: "\t196403273813\n", trinity_subscriber_id: 1})
      trinity_sub = build_trinity_sub(%{national_id: "196403273813"})

      capway_data = %{"C-001" => capway_sub}
      trinity_data = %{1 => trinity_sub}

      result = CompareDataV2.get_customers_to_update(capway_data, trinity_data)

      assert map_size(result) == 0
    end
  end

  describe "get_customers_to_update/2 email mismatch" do
    test "marks customer for update when emails differ" do
      capway_sub =
        build_capway_sub(%{
          national_id: "196403273813",
          trinity_subscriber_id: 1,
          collection: 0,
          email: "old@example.com"
        })

      trinity_sub =
        build_trinity_sub(%{national_id: "196403273813", email: "new@example.com"})

      capway_data = %{"C-001" => capway_sub}
      trinity_data = %{1 => trinity_sub}

      result = CompareDataV2.get_customers_to_update(capway_data, trinity_data)

      assert map_size(result) == 1
      action_item = Map.get(result, "C-001")
      assert action_item.action == :capway_update_customer
      assert action_item.sub_action == [:update_email]
      assert action_item.comment == "Email mismatch"
    end

    test "uses combined reason when both national_id and email differ" do
      capway_sub =
        build_capway_sub(%{
          national_id: "198507099805",
          trinity_subscriber_id: 1,
          collection: 0,
          email: "old@example.com"
        })

      trinity_sub =
        build_trinity_sub(%{national_id: "196403273813", email: "new@example.com"})

      capway_data = %{"C-001" => capway_sub}
      trinity_data = %{1 => trinity_sub}

      result = CompareDataV2.get_customers_to_update(capway_data, trinity_data)

      action_item = Map.get(result, "C-001")
      assert action_item.action == :capway_update_customer
      assert action_item.sub_action == [:update_nin, :update_email]
      assert action_item.comment == "National ID and email mismatch"
    end

    test "does not include actual emails in reason text (PII)" do
      capway_sub =
        build_capway_sub(%{
          national_id: "196403273813",
          trinity_subscriber_id: 1,
          collection: 0,
          email: "secret-old@example.com"
        })

      trinity_sub =
        build_trinity_sub(%{national_id: "196403273813", email: "secret-new@example.com"})

      capway_data = %{"C-001" => capway_sub}
      trinity_data = %{1 => trinity_sub}

      result = CompareDataV2.get_customers_to_update(capway_data, trinity_data)
      action_item = Map.get(result, "C-001")

      refute String.contains?(action_item.comment, "secret-old@example.com")
      refute String.contains?(action_item.comment, "secret-new@example.com")
    end

    test "treats email comparison as case-insensitive and trim-insensitive" do
      capway_sub =
        build_capway_sub(%{
          national_id: "196403273813",
          trinity_subscriber_id: 1,
          collection: 0,
          email: "  Same@Example.COM  "
        })

      trinity_sub = build_trinity_sub(%{national_id: "196403273813", email: "same@example.com"})

      capway_data = %{"C-001" => capway_sub}
      trinity_data = %{1 => trinity_sub}

      assert CompareDataV2.get_customers_to_update(capway_data, trinity_data) == %{}
    end

    test "does not mark when capway email is nil (unknown)" do
      capway_sub =
        build_capway_sub(%{
          national_id: "196403273813",
          trinity_subscriber_id: 1,
          collection: 0,
          email: nil
        })

      trinity_sub =
        build_trinity_sub(%{national_id: "196403273813", email: "new@example.com"})

      capway_data = %{"C-001" => capway_sub}
      trinity_data = %{1 => trinity_sub}

      assert CompareDataV2.get_customers_to_update(capway_data, trinity_data) == %{}
    end

    test "does not mark when trinity email is nil" do
      capway_sub =
        build_capway_sub(%{
          national_id: "196403273813",
          trinity_subscriber_id: 1,
          collection: 0,
          email: "old@example.com"
        })

      trinity_sub = build_trinity_sub(%{national_id: "196403273813", email: nil})

      capway_data = %{"C-001" => capway_sub}
      trinity_data = %{1 => trinity_sub}

      assert CompareDataV2.get_customers_to_update(capway_data, trinity_data) == %{}
    end

    test "does not mark when either email is blank" do
      capway_sub =
        build_capway_sub(%{
          national_id: "196403273813",
          trinity_subscriber_id: 1,
          collection: 0,
          email: ""
        })

      trinity_sub =
        build_trinity_sub(%{national_id: "196403273813", email: "new@example.com"})

      capway_data = %{"C-001" => capway_sub}
      trinity_data = %{1 => trinity_sub}

      assert CompareDataV2.get_customers_to_update(capway_data, trinity_data) == %{}
    end

    test "respects collection >= 2 cap and capway_sync_excluded for email-only diffs" do
      capway_sub =
        build_capway_sub(%{
          national_id: "196403273813",
          trinity_subscriber_id: 1,
          collection: 5,
          email: "old@example.com"
        })

      trinity_sub =
        build_trinity_sub(%{national_id: "196403273813", email: "new@example.com"})

      capway_data = %{"C-001" => capway_sub}
      trinity_data = %{1 => trinity_sub}

      assert CompareDataV2.get_customers_to_update(capway_data, trinity_data) == %{}

      excluded_trinity =
        build_trinity_sub(%{
          national_id: "196403273813",
          email: "new@example.com",
          capway_sync_excluded: true
        })

      assert CompareDataV2.get_customers_to_update(
               capway_data,
               %{1 => excluded_trinity}
             ) == %{}
    end
  end

  describe "get_customers_to_update/2 language mismatch (:se market → \"sv\")" do
    test "flags a wrong language code on its own" do
      capway_sub =
        build_capway_sub(%{
          national_id: "196403273813",
          trinity_subscriber_id: 1,
          collection: 0,
          language_code: "en"
        })

      trinity_sub = build_trinity_sub(%{national_id: "196403273813"})

      result =
        CompareDataV2.get_customers_to_update(%{"C-001" => capway_sub}, %{1 => trinity_sub})

      assert map_size(result) == 1
      action_item = Map.get(result, "C-001")
      assert action_item.action == :capway_update_customer
      assert action_item.sub_action == [:update_language]
      assert action_item.comment == "Language code mismatch"
    end

    test "flags a fetched-but-blank language as wrong" do
      capway_sub =
        build_capway_sub(%{
          national_id: "196403273813",
          trinity_subscriber_id: 1,
          collection: 0,
          language_code: ""
        })

      trinity_sub = build_trinity_sub(%{national_id: "196403273813"})

      result =
        CompareDataV2.get_customers_to_update(%{"C-001" => capway_sub}, %{1 => trinity_sub})

      assert map_size(result) == 1
      assert Map.get(result, "C-001").sub_action == [:update_language]
    end

    test "does not flag a never-fetched language (nil is unknown)" do
      capway_sub =
        build_capway_sub(%{
          national_id: "196403273813",
          trinity_subscriber_id: 1,
          collection: 0,
          language_code: nil
        })

      trinity_sub = build_trinity_sub(%{national_id: "196403273813"})

      result =
        CompareDataV2.get_customers_to_update(%{"C-001" => capway_sub}, %{1 => trinity_sub})

      assert map_size(result) == 0
    end

    test "treats language comparison as case- and trim-insensitive" do
      capway_sub =
        build_capway_sub(%{
          national_id: "196403273813",
          trinity_subscriber_id: 1,
          collection: 0,
          language_code: "  SV  "
        })

      trinity_sub = build_trinity_sub(%{national_id: "196403273813"})

      assert CompareDataV2.get_customers_to_update(
               %{"C-001" => capway_sub},
               %{1 => trinity_sub}
             ) == %{}
    end

    test "combines language with national_id in sub_action and reason" do
      capway_sub =
        build_capway_sub(%{
          national_id: "198507099805",
          trinity_subscriber_id: 1,
          collection: 0,
          language_code: "en"
        })

      trinity_sub = build_trinity_sub(%{national_id: "196403273813"})

      result =
        CompareDataV2.get_customers_to_update(%{"C-001" => capway_sub}, %{1 => trinity_sub})

      action_item = Map.get(result, "C-001")
      assert action_item.sub_action == [:update_nin, :update_language]
      assert action_item.comment == "National ID and language code mismatch"
    end

    test "combines all three fields in canonical order" do
      capway_sub =
        build_capway_sub(%{
          national_id: "198507099805",
          trinity_subscriber_id: 1,
          collection: 0,
          email: "old@example.com",
          language_code: "en"
        })

      trinity_sub =
        build_trinity_sub(%{national_id: "196403273813", email: "new@example.com"})

      result =
        CompareDataV2.get_customers_to_update(%{"C-001" => capway_sub}, %{1 => trinity_sub})

      action_item = Map.get(result, "C-001")
      assert action_item.sub_action == [:update_nin, :update_email, :update_language]
      assert action_item.comment == "National ID, email and language code mismatch"
    end

    test "respects the collection >= 2 cap for language-only diffs" do
      capway_sub =
        build_capway_sub(%{
          national_id: "196403273813",
          trinity_subscriber_id: 1,
          collection: 2,
          language_code: "en"
        })

      trinity_sub = build_trinity_sub(%{national_id: "196403273813"})

      assert CompareDataV2.get_customers_to_update(
               %{"C-001" => capway_sub},
               %{1 => trinity_sub}
             ) == %{}
    end
  end

  describe "get_customers_to_update/2 currency mismatch (:se market → \"SEK\")" do
    test "flags a wrong currency code on its own" do
      capway_sub =
        build_capway_sub(%{
          national_id: "196403273813",
          trinity_subscriber_id: 1,
          collection: 0,
          currency_code: "NOK"
        })

      trinity_sub = build_trinity_sub(%{national_id: "196403273813"})

      result =
        CompareDataV2.get_customers_to_update(%{"C-001" => capway_sub}, %{1 => trinity_sub})

      assert map_size(result) == 1
      action_item = Map.get(result, "C-001")
      assert action_item.sub_action == [:update_currency]
      assert action_item.comment == "Currency code mismatch"
    end

    test "flags a fetched-but-blank currency as wrong" do
      capway_sub =
        build_capway_sub(%{
          national_id: "196403273813",
          trinity_subscriber_id: 1,
          collection: 0,
          currency_code: ""
        })

      trinity_sub = build_trinity_sub(%{national_id: "196403273813"})

      result =
        CompareDataV2.get_customers_to_update(%{"C-001" => capway_sub}, %{1 => trinity_sub})

      assert Map.get(result, "C-001").sub_action == [:update_currency]
    end

    test "does not flag a never-fetched currency (nil is unknown)" do
      capway_sub =
        build_capway_sub(%{
          national_id: "196403273813",
          trinity_subscriber_id: 1,
          collection: 0,
          currency_code: nil
        })

      trinity_sub = build_trinity_sub(%{national_id: "196403273813"})

      assert CompareDataV2.get_customers_to_update(
               %{"C-001" => capway_sub},
               %{1 => trinity_sub}
             ) == %{}
    end

    test "treats currency comparison as case- and trim-insensitive" do
      capway_sub =
        build_capway_sub(%{
          national_id: "196403273813",
          trinity_subscriber_id: 1,
          collection: 0,
          currency_code: "  sek  "
        })

      trinity_sub = build_trinity_sub(%{national_id: "196403273813"})

      assert CompareDataV2.get_customers_to_update(
               %{"C-001" => capway_sub},
               %{1 => trinity_sub}
             ) == %{}
    end

    test "combines all four fields in canonical order" do
      capway_sub =
        build_capway_sub(%{
          national_id: "198507099805",
          trinity_subscriber_id: 1,
          collection: 0,
          email: "old@example.com",
          language_code: "en",
          currency_code: "NOK"
        })

      trinity_sub =
        build_trinity_sub(%{national_id: "196403273813", email: "new@example.com"})

      result =
        CompareDataV2.get_customers_to_update(%{"C-001" => capway_sub}, %{1 => trinity_sub})

      action_item = Map.get(result, "C-001")

      assert action_item.sub_action ==
               [:update_nin, :update_email, :update_language, :update_currency]

      assert action_item.comment ==
               "National ID, email, language code and currency code mismatch"
    end
  end

  describe "get_contracts_to_update/2" do
    test "marks contract for update when subscriber_id mismatches but national_id matches" do
      # Both have same national_id, but subscriber_id on capway struct differs from trinity struct
      capway_sub =
        build_capway_sub(%{
          national_id: "196403273813",
          trinity_subscriber_id: 1,
          collection: 0
        })

      # Force subscriber_id mismatch by setting a different value on the trinity struct
      trinity_sub = build_trinity_sub(%{national_id: "196403273813", trinity_subscriber_id: 2})

      capway_data = %{"C-001" => capway_sub}
      trinity_data = %{1 => trinity_sub}

      result = CompareDataV2.get_contracts_to_update(capway_data, trinity_data)

      assert map_size(result) == 1
      assert Map.has_key?(result, "C-001")
      action_item = Map.get(result, "C-001")
      assert action_item.action == :capway_update_contract
      assert action_item.comment == "Subscriber ID mismatch"
    end

    test "does not mark contract for update when national_id differs (handled by get_customers_to_update)" do
      capway_sub = build_capway_sub(%{national_id: "198507099805", trinity_subscriber_id: 1, collection: 0})
      trinity_sub = build_trinity_sub(%{national_id: "196403273813"})

      capway_data = %{"C-001" => capway_sub}
      trinity_data = %{1 => trinity_sub}

      result = CompareDataV2.get_contracts_to_update(capway_data, trinity_data)

      assert map_size(result) == 0
    end

    test "does not mark contract for update when everything matches" do
      capway_sub = build_capway_sub(%{national_id: "196403273813", trinity_subscriber_id: 1})
      trinity_sub = build_trinity_sub(%{national_id: "196403273813"})

      capway_data = %{"C-001" => capway_sub}
      trinity_data = %{1 => trinity_sub}

      result = CompareDataV2.get_contracts_to_update(capway_data, trinity_data)

      assert map_size(result) == 0
    end

    test "treats national_ids that differ only by whitespace as matching for subscriber_id mismatch" do
      capway_sub =
        build_capway_sub(%{
          national_id: "196403273813",
          trinity_subscriber_id: 1,
          collection: 0
        })

      trinity_sub =
        build_trinity_sub(%{national_id: "196403 273813 ", trinity_subscriber_id: 2})

      capway_data = %{"C-001" => capway_sub}
      trinity_data = %{1 => trinity_sub}

      result = CompareDataV2.get_contracts_to_update(capway_data, trinity_data)

      assert map_size(result) == 1
      action_item = Map.get(result, "C-001")
      assert action_item.action == :capway_update_contract
      assert action_item.comment == "Subscriber ID mismatch"
    end
  end

  describe "run/3 update/cancel exclusion" do
    test "national_id mismatch goes to update_customers, not update_contracts" do
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
            associated_subscribers: %{
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

      # C-001 should be in update_customers (national ID mismatch), not update_contracts
      assert Map.has_key?(result.actions.capway.update_customers, "C-001")
      refute Map.has_key?(result.actions.capway.update_contracts, "C-001")
      refute Map.has_key?(result.actions.capway.cancel_contracts, "C-001")

      # C-002 should be in cancel (not in update)
      assert Map.has_key?(result.actions.capway.cancel_contracts, "C-002")
      refute Map.has_key?(result.actions.capway.update_contracts, "C-002")
      refute Map.has_key?(result.actions.capway.update_customers, "C-002")
    end

    test "contract with collection >= 2 excluded from update_customers does not end up in cancel" do
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
            associated_subscribers: %{"C-collect" => capway_sub},
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
      refute Map.has_key?(result.actions.capway.update_customers, "C-collect")
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
            associated_subscribers: %{},
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
            associated_subscribers: %{},
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

    test "enriches create action item with capway references from inactive contract" do
      # Trinity subscriber is active but Capway contract is inactive
      active_sub =
        build_trinity_sub(%{
          trinity_subscriber_id: 1,
          national_id: "196403273813",
          trinity_subscription_updated_at: ~N[2025-01-01 00:00:00]
        })

      # Inactive Capway contract for the same subscriber
      inactive_capway_sub =
        build_capway_sub(%{
          national_id: "196403273813",
          trinity_subscriber_id: 1,
          capway_active_status: false,
          capway_contract_ref: "C-INACTIVE",
          capway_contract_guid: "GUID-123",
          capway_customer_id: "CID-456"
        })

      args = %{
        data: %{
          capway: %{
            active_subscribers: %{},
            associated_subscribers: %{"C-INACTIVE" => inactive_capway_sub},
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
      action_item = Map.get(result.actions.capway.create_contracts, 1)
      assert action_item.capway_customer_id == "CID-456"
      assert action_item.capway_contract_guid == "GUID-123"
      assert action_item.capway_contract_ref == "C-INACTIVE"
    end

    test "create action item has nil capway references when no capway contract exists" do
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
            associated_subscribers: %{},
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
      action_item = Map.get(result.actions.capway.create_contracts, 1)
      assert action_item.capway_customer_id == nil
      assert action_item.capway_contract_guid == nil
      assert action_item.capway_contract_ref == nil
    end
  end

  describe "get_mandates_to_create/2" do
    defp build_autogiro_sub(attrs) do
      build_trinity_sub(
        Map.merge(
          %{
            payment_method: "capway_autogiro",
            trinity_subscription_updated_at: ~N[2025-01-01 00:00:00]
          },
          attrs
        )
      )
    end

    test "emits capway_create_mandate for active autogiro subscriber without mandate metadata" do
      sub = build_autogiro_sub(%{trinity_subscriber_id: 1, national_id: "196403273813"})

      result = CompareDataV2.get_mandates_to_create(%{1 => sub})

      assert map_size(result) == 1
      action_item = Map.get(result, 1)
      assert action_item.action == :capway_create_mandate
      assert action_item.comment == "Capway autogiro mandate missing"
      assert action_item.trinity_subscriber_id == 1
      assert action_item.national_id == "196403273813"
      assert action_item.status == :pending
      assert action_item.sub_action == nil
    end

    test "matches the space variant of the payment method" do
      sub =
        build_autogiro_sub(%{
          trinity_subscriber_id: 2,
          payment_method: "capway autogiro"
        })

      result = CompareDataV2.get_mandates_to_create(%{2 => sub})

      assert map_size(result) == 1
      assert Map.get(result, 2).action == :capway_create_mandate
    end

    test "skips subscriber with a stored mandate guid" do
      sub =
        build_autogiro_sub(%{
          trinity_subscriber_id: 1,
          trinity_capway_mandate_guid: "6f9619ff-8b86-d011-b42d-00cf4fc964ff"
        })

      assert CompareDataV2.get_mandates_to_create(%{1 => sub}) == %{}
    end

    test "treats a blank mandate guid as missing" do
      sub = build_autogiro_sub(%{trinity_subscriber_id: 1, trinity_capway_mandate_guid: "   "})

      result = CompareDataV2.get_mandates_to_create(%{1 => sub})

      assert map_size(result) == 1
    end

    test "ignores non-autogiro payment methods" do
      capway_sub = build_autogiro_sub(%{trinity_subscriber_id: 1, payment_method: "capway"})
      card_sub = build_autogiro_sub(%{trinity_subscriber_id: 2, payment_method: "card"})

      assert CompareDataV2.get_mandates_to_create(%{1 => capway_sub, 2 => card_sub}) == %{}
    end

    test "skips sync-excluded subscribers" do
      sub = build_autogiro_sub(%{trinity_subscriber_id: 1, capway_sync_excluded: true})

      assert CompareDataV2.get_mandates_to_create(%{1 => sub}) == %{}
    end

    test "skips subscriptions updated within the last day" do
      recent_sub =
        build_autogiro_sub(%{
          trinity_subscriber_id: 1,
          trinity_subscription_updated_at: NaiveDateTime.utc_now()
        })

      never_updated_sub =
        build_autogiro_sub(%{
          trinity_subscriber_id: 2,
          trinity_subscription_updated_at: nil
        })

      assert CompareDataV2.get_mandates_to_create(%{1 => recent_sub, 2 => never_updated_sub}) ==
               %{}
    end

    test "includes the recorded failure reason and timestamp in the comment" do
      sub =
        build_autogiro_sub(%{
          trinity_subscriber_id: 1,
          trinity_capway_mandate_error: "Personen saknar giltigt personnummer",
          trinity_capway_mandate_error_at: "2026-07-20T22:15:00Z"
        })

      result = CompareDataV2.get_mandates_to_create(%{1 => sub})

      assert Map.get(result, 1).comment ==
               "Capway autogiro mandate missing — last attempt failed: " <>
                 "Personen saknar giltigt personnummer (2026-07-20T22:15:00Z)"
    end

    test "includes the failure reason without a timestamp when none was recorded" do
      sub =
        build_autogiro_sub(%{
          trinity_subscriber_id: 1,
          trinity_capway_mandate_error: "missing_personal_number"
        })

      result = CompareDataV2.get_mandates_to_create(%{1 => sub})

      assert Map.get(result, 1).comment ==
               "Capway autogiro mandate missing — last attempt failed: missing_personal_number"
    end

    test "enriches action item with capway references from a matching contract" do
      sub = build_autogiro_sub(%{trinity_subscriber_id: 1, national_id: "196403273813"})

      capway_sub =
        build_capway_sub(%{
          national_id: "196403273813",
          trinity_subscriber_id: 1,
          capway_contract_ref: "C-001",
          capway_contract_guid: "GUID-123",
          capway_customer_id: "CID-456"
        })

      result = CompareDataV2.get_mandates_to_create(%{1 => sub}, %{"C-001" => capway_sub})

      action_item = Map.get(result, 1)
      assert action_item.capway_customer_id == "CID-456"
      assert action_item.capway_contract_guid == "GUID-123"
      assert action_item.capway_contract_ref == "C-001"
    end

    test "run/3 includes the create_mandates bucket" do
      autogiro_sub =
        build_autogiro_sub(%{trinity_subscriber_id: 1, national_id: "196403273813"})

      args = %{
        data: %{
          capway: %{
            active_subscribers: %{},
            associated_subscribers: %{},
            above_collector_threshold: %{},
            map_sets: %{
              active_trinity_ids: MapSet.new(),
              active_national_ids: MapSet.new()
            }
          },
          trinity: %{
            active_subscribers: %{1 => autogiro_sub},
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

      assert map_size(result.actions.capway.create_mandates) == 1
      assert Map.get(result.actions.capway.create_mandates, 1).action == :capway_create_mandate
      # autogiro subscriptions are not eligible for contract creation items
      assert map_size(result.actions.capway.create_contracts) == 0
    end
  end

  describe "capway_sync_excluded" do
    test "excluded subscriber does not generate create_contracts action" do
      excluded_sub =
        build_trinity_sub(%{
          trinity_subscriber_id: 1,
          national_id: "196403273813",
          trinity_subscription_updated_at: ~N[2025-01-01 00:00:00],
          capway_sync_excluded: true
        })

      args = %{
        data: %{
          capway: %{
            active_subscribers: %{},
            associated_subscribers: %{},
            above_collector_threshold: %{},
            map_sets: %{
              active_trinity_ids: MapSet.new(),
              active_national_ids: MapSet.new()
            }
          },
          trinity: %{
            active_subscribers: %{1 => excluded_sub},
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

      assert map_size(result.actions.capway.create_contracts) == 0
    end

    test "excluded subscriber does not trigger capway contract cancellation" do
      # Capway has a contract for subscriber 1, and Trinity has the subscriber but excluded.
      # The contract should NOT be cancelled because the subscriber is still present in active_subscribers.
      excluded_sub =
        build_trinity_sub(%{
          trinity_subscriber_id: 1,
          national_id: "196403273813",
          capway_sync_excluded: true
        })

      capway_sub =
        build_capway_sub(%{
          trinity_subscriber_id: 1,
          national_id: "196403273813",
          capway_contract_ref: "C-001"
        })

      args = %{
        data: %{
          capway: %{
            active_subscribers: %{"C-001" => capway_sub},
            associated_subscribers: %{"C-001" => capway_sub},
            above_collector_threshold: %{},
            map_sets: %{
              active_trinity_ids: MapSet.new([1]),
              active_national_ids: MapSet.new(["196403273813"])
            }
          },
          trinity: %{
            active_subscribers: %{1 => excluded_sub},
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

      # No cancellation — subscriber is still visible in active data
      assert map_size(result.actions.capway.cancel_contracts) == 0
      # No updates either — subscriber is excluded from sync
      assert map_size(result.actions.capway.update_customers) == 0
      assert map_size(result.actions.capway.update_contracts) == 0
    end

    test "excluded subscriber does not generate update_customers action on national_id mismatch" do
      capway_sub =
        build_capway_sub(%{
          national_id: "198507099805",
          trinity_subscriber_id: 1,
          collection: 0
        })

      excluded_trinity_sub =
        build_trinity_sub(%{
          national_id: "196403273813",
          capway_sync_excluded: true
        })

      capway_data = %{"C-001" => capway_sub}
      trinity_data = %{1 => excluded_trinity_sub}

      result = CompareDataV2.get_customers_to_update(capway_data, trinity_data)

      assert map_size(result) == 0
    end

    test "excluded subscriber does not generate update_contracts action on subscriber_id mismatch" do
      capway_sub =
        build_capway_sub(%{
          national_id: "196403273813",
          trinity_subscriber_id: 1,
          collection: 0
        })

      excluded_trinity_sub =
        build_trinity_sub(%{
          national_id: "196403273813",
          trinity_subscriber_id: 2,
          capway_sync_excluded: true
        })

      capway_data = %{"C-001" => capway_sub}
      trinity_data = %{1 => excluded_trinity_sub}

      result = CompareDataV2.get_contracts_to_update(capway_data, trinity_data)

      assert map_size(result) == 0
    end

    test "excluded subscriber does not generate suspend or cancel action" do
      capway_sub = build_capway_sub(%{collection: 3, last_invoice_status: "Invoice"})

      excluded_trinity_sub =
        build_trinity_sub(%{capway_sync_excluded: true})

      capway_data = %{"C-001" => capway_sub}
      trinity_data = %{1 => excluded_trinity_sub}
      trinity_map_set = %{active_national_ids: MapSet.new(["199001011234"])}

      {suspend, cancel} =
        CompareDataV2.get_accounts_to_suspend_or_cancel(
          capway_data,
          trinity_data,
          trinity_map_set
        )

      assert map_size(suspend) == 0
      assert map_size(cancel) == 0
    end

    test "excluded locked subscriber does not generate suspend action" do
      capway_sub = build_capway_sub(%{collection: 3})

      excluded_trinity_sub =
        build_trinity_sub(%{
          subscription_type: :locked,
          capway_sync_excluded: true
        })

      capway_data = %{"C-001" => capway_sub}
      trinity_data = %{1 => excluded_trinity_sub}
      trinity_map_set = %{active_national_ids: MapSet.new(["199001011234"])}

      {suspend, cancel} =
        CompareDataV2.get_accounts_to_suspend_or_cancel(
          capway_data,
          trinity_data,
          trinity_map_set
        )

      assert map_size(suspend) == 0
      assert map_size(cancel) == 0
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

  describe "sub_action emission" do
    test "non-update_customer action items have sub_action: nil" do
      capway_active = build_capway_sub(%{collection: 4, last_invoice_status: "Invoice"})
      trinity_active = build_trinity_sub(%{})

      {_suspend, cancel} =
        CompareDataV2.get_accounts_to_suspend_or_cancel(
          %{"C-001" => capway_active},
          %{1 => trinity_active},
          %{active_national_ids: MapSet.new()}
        )

      assert %{sub_action: nil, action: :trinity_cancel_subscription} =
               Map.get(cancel, "C-001")

      capway_locked = build_capway_sub(%{collection: 4, last_invoice_status: "Invoice"})
      trinity_locked = build_trinity_sub(%{subscription_type: :locked})

      {suspend, _cancel} =
        CompareDataV2.get_accounts_to_suspend_or_cancel(
          %{"C-002" => capway_locked},
          %{1 => trinity_locked},
          %{active_national_ids: MapSet.new()}
        )

      assert %{sub_action: nil, action: :suspend} = Map.get(suspend, "C-002")

      capway_subid_mismatch =
        build_capway_sub(%{
          national_id: "196403273813",
          trinity_subscriber_id: 1,
          collection: 0
        })

      trinity_subid_mismatch =
        build_trinity_sub(%{national_id: "196403273813", trinity_subscriber_id: 2})

      update_contract_result =
        CompareDataV2.get_contracts_to_update(
          %{"C-003" => capway_subid_mismatch},
          %{1 => trinity_subid_mismatch}
        )

      assert %{sub_action: nil, action: :capway_update_contract} =
               Map.get(update_contract_result, "C-003")

      trinity_to_create =
        build_trinity_sub(%{
          trinity_subscriber_id: 99,
          national_id: "199001011234",
          payment_method: "capway",
          trinity_subscription_updated_at: ~U[2020-01-01 00:00:00Z]
        })

      capway_map_sets = %{
        active_trinity_ids: MapSet.new(),
        active_national_ids: MapSet.new()
      }

      create_result =
        CompareDataV2.get_contracts_to_create(
          %{99 => trinity_to_create},
          capway_map_sets,
          %{}
        )

      assert %{sub_action: nil, action: :capway_create_contract} = Map.get(create_result, 99)

      capway_orphan = build_capway_sub(%{trinity_subscriber_id: 999, national_id: "200001011234"})

      cancel_result =
        CompareDataV2.get_contracts_to_cancel(
          %{"C-004" => capway_orphan},
          %{}
        )

      assert %{sub_action: nil, action: :capway_cancel_contract} = Map.get(cancel_result, "C-004")
    end
  end
end
