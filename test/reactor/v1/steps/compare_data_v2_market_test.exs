defmodule CapwaySync.Reactor.V1.Steps.CompareDataV2MarketTest do
  # async: false — these tests flip the global :capway_sync, :market env, so they
  # must not run concurrently with tests that assume the default :se market.
  use ExUnit.Case, async: false

  alias CapwaySync.Reactor.V1.Steps.CompareDataV2
  alias CapwaySync.Models.Subscribers.Canonical

  # Most tests here run under the :no market (expected language/currency
  # "nb"/"NOK"); seed the Capway side with those so non-language/currency tests
  # don't incidentally flag a mismatch. The :se contrast test overrides them.
  defp build_capway_sub(attrs) do
    Map.merge(
      %Canonical{
        national_id: "24105144829",
        trinity_subscriber_id: 1,
        trinity_subscription_id: 100,
        capway_contract_ref: "C-001",
        capway_customer_id: "CID-001",
        capway_active_status: true,
        origin: :capway,
        collection: 0,
        last_invoice_status: "Invoice",
        payment_method: nil,
        trinity_status: nil,
        subscription_type: nil,
        language_code: "nb",
        currency_code: "NOK"
      },
      attrs
    )
  end

  defp build_trinity_sub(attrs) do
    Map.merge(
      %Canonical{
        national_id: "24105144829",
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

  defp put_market(market) do
    previous = Application.get_env(:capway_sync, :market)
    Application.put_env(:capway_sync, :market, market)
    on_exit(fn -> Application.put_env(:capway_sync, :market, previous) end)
  end

  describe "get_customers_to_update/2 in the Norwegian (:no) market" do
    setup do
      put_market(:no)
      :ok
    end

    test "does not flag a Norwegian number written with an internal space (the reported case)" do
      # Norwegian fødselsnummer are commonly written "DDMMYY NNNNN". The Capway
      # side arrives trimmed/space-free while Trinity stores the spaced form.
      capway_sub = build_capway_sub(%{national_id: "24105144829", trinity_subscriber_id: 1})
      trinity_sub = build_trinity_sub(%{national_id: "241051 44829"})

      capway_data = %{"C-001" => capway_sub}
      trinity_data = %{1 => trinity_sub}

      result = CompareDataV2.get_customers_to_update(capway_data, trinity_data)

      assert map_size(result) == 0
    end

    test "does not flag when national_ids differ only by trailing whitespace" do
      capway_sub = build_capway_sub(%{national_id: "24105144829", trinity_subscriber_id: 1})
      trinity_sub = build_trinity_sub(%{national_id: "24105144829 "})

      capway_data = %{"C-001" => capway_sub}
      trinity_data = %{1 => trinity_sub}

      result = CompareDataV2.get_customers_to_update(capway_data, trinity_data)

      assert map_size(result) == 0
    end

    test "still flags a genuine national_id difference (no SE validity gate applied)" do
      # Two different Norwegian numbers — neither is a valid SE personnummer, so
      # this only flags because the :no market skips the validity gate.
      capway_sub = build_capway_sub(%{national_id: "24105144829", trinity_subscriber_id: 1})
      trinity_sub = build_trinity_sub(%{national_id: "31125099912"})

      capway_data = %{"C-001" => capway_sub}
      trinity_data = %{1 => trinity_sub}

      result = CompareDataV2.get_customers_to_update(capway_data, trinity_data)

      assert map_size(result) == 1
      action_item = Map.get(result, "C-001")
      assert action_item.action == :capway_update_customer
      assert action_item.comment == "National ID mismatch"
    end
  end

  describe "market gating contrast for the same Norwegian number" do
    test ":se market suppresses the mismatch (Norwegian number fails Personnummer.valid?)" do
      put_market(:se)

      capway_sub =
        build_capway_sub(%{
          national_id: "24105144829",
          trinity_subscriber_id: 1,
          language_code: "sv",
          currency_code: "SEK"
        })

      trinity_sub = build_trinity_sub(%{national_id: "31125099912"})

      capway_data = %{"C-001" => capway_sub}
      trinity_data = %{1 => trinity_sub}

      result = CompareDataV2.get_customers_to_update(capway_data, trinity_data)

      assert map_size(result) == 0
    end
  end

  describe "language code gating per market" do
    test ":no market flags \"sv\" (Swedish) language as wrong" do
      put_market(:no)

      capway_sub =
        build_capway_sub(%{
          national_id: "24105144829",
          trinity_subscriber_id: 1,
          language_code: "sv"
        })

      trinity_sub = build_trinity_sub(%{national_id: "24105144829"})

      result =
        CompareDataV2.get_customers_to_update(%{"C-001" => capway_sub}, %{1 => trinity_sub})

      assert map_size(result) == 1
      action_item = Map.get(result, "C-001")
      assert action_item.sub_action == [:update_language]
      assert action_item.comment == "Language code mismatch"
    end

    test ":no market accepts \"nb\" (Norwegian) language" do
      put_market(:no)

      capway_sub =
        build_capway_sub(%{
          national_id: "24105144829",
          trinity_subscriber_id: 1,
          language_code: "nb"
        })

      trinity_sub = build_trinity_sub(%{national_id: "24105144829"})

      assert CompareDataV2.get_customers_to_update(
               %{"C-001" => capway_sub},
               %{1 => trinity_sub}
             ) == %{}
    end

    test "a market with no defined language/currency never flags those mismatches" do
      put_market(:dk)

      capway_sub =
        build_capway_sub(%{
          national_id: "24105144829",
          trinity_subscriber_id: 1,
          language_code: "anything",
          currency_code: "XYZ"
        })

      trinity_sub = build_trinity_sub(%{national_id: "24105144829"})

      assert CompareDataV2.get_customers_to_update(
               %{"C-001" => capway_sub},
               %{1 => trinity_sub}
             ) == %{}
    end

    test ":no market flags \"SEK\" currency as wrong (expects \"NOK\")" do
      put_market(:no)

      capway_sub =
        build_capway_sub(%{
          national_id: "24105144829",
          trinity_subscriber_id: 1,
          currency_code: "SEK"
        })

      trinity_sub = build_trinity_sub(%{national_id: "24105144829"})

      result =
        CompareDataV2.get_customers_to_update(%{"C-001" => capway_sub}, %{1 => trinity_sub})

      assert map_size(result) == 1
      action_item = Map.get(result, "C-001")
      assert action_item.sub_action == [:update_currency]
      assert action_item.comment == "Currency code mismatch"
    end
  end
end
