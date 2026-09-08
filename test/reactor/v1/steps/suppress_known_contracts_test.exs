defmodule CapwaySync.Reactor.V1.Steps.SuppressKnownContractsTest do
  @moduledoc """
  Tests the backstop that drops `:capway_create_contract` items when the
  `capway-contracts` table still holds a recently written active contract for
  the subscriber. Mirrors the real incident: contract `v2:1780472140:875617`
  was active in the 2026-09-01 snapshot, absent from the 2026-09-02 fetch, and
  the subscriber was flagged "Missing in Capway system".
  """
  use ExUnit.Case, async: true
  import ExUnit.CaptureLog

  alias CapwaySync.Reactor.V1.Steps.SuppressKnownContracts
  alias CapwaySync.Models.CapwaySubscriber
  alias CapwaySync.Models.Dynamodb.ActionItem

  @now ~U[2026-09-02 10:01:56Z]

  defp create_item(attrs) do
    ActionItem.create_action_item(
      :capway_create_contract,
      Map.merge(
        %{
          national_id: "195503180266",
          trinity_subscriber_id: 62805,
          trinity_subscription_id: 65200,
          reason: "Missing in Capway system"
        },
        attrs
      )
    )
  end

  defp contract(attrs) do
    Map.merge(
      %CapwaySubscriber{
        contract_ref_no: "v2:1780472140:875617",
        customer_id: "307543",
        customer_ref: "v2-875617-62805-GM8uo",
        id_number: "195503180266",
        active: "true",
        updated_at: "2026-09-01T22:04:51.448559Z"
      },
      attrs
    )
  end

  defp lookup_returning(contracts), do: fn _national_id -> {:ok, contracts} end

  describe "recently_active?/3" do
    test "true for an active contract written within the age window" do
      assert SuppressKnownContracts.recently_active?(contract(%{}), @now, 3)
    end

    test "false for an inactive contract" do
      refute SuppressKnownContracts.recently_active?(contract(%{active: "false"}), @now, 3)
      refute SuppressKnownContracts.recently_active?(contract(%{active: nil}), @now, 3)
    end

    test "false when the stored row is older than the age window" do
      old = contract(%{updated_at: "2026-08-20T00:00:00Z"})
      refute SuppressKnownContracts.recently_active?(old, @now, 3)
      # exactly at the boundary still counts
      boundary = contract(%{updated_at: "2026-08-30T10:01:56Z"})
      assert SuppressKnownContracts.recently_active?(boundary, @now, 3)
    end

    test "false when updated_at is missing or unparsable" do
      refute SuppressKnownContracts.recently_active?(contract(%{updated_at: nil}), @now, 3)

      refute SuppressKnownContracts.recently_active?(
               contract(%{updated_at: "yesterday"}),
               @now,
               3
             )
    end
  end

  describe "known_active_contract/4" do
    test "returns the matching active contract" do
      item = create_item(%{})

      assert %CapwaySubscriber{contract_ref_no: "v2:1780472140:875617"} =
               SuppressKnownContracts.known_active_contract(
                 item,
                 lookup_returning([contract(%{})]),
                 @now,
                 3
               )
    end

    test "skips inactive and stale rows but finds an active one among them" do
      rows = [
        contract(%{contract_ref_no: "old", active: "false"}),
        contract(%{contract_ref_no: "stale", updated_at: "2026-07-01T00:00:00Z"}),
        contract(%{contract_ref_no: "live"})
      ]

      assert %{contract_ref_no: "live"} =
               SuppressKnownContracts.known_active_contract(
                 create_item(%{}),
                 lookup_returning(rows),
                 @now,
                 3
               )
    end

    test "nil when nothing is stored" do
      assert nil ==
               SuppressKnownContracts.known_active_contract(
                 create_item(%{}),
                 lookup_returning([]),
                 @now,
                 3
               )
    end

    test "nil without a national id, and never calls the lookup" do
      lookup = fn _ -> flunk("lookup must not be called") end

      assert nil ==
               SuppressKnownContracts.known_active_contract(
                 create_item(%{national_id: nil}),
                 lookup,
                 @now,
                 3
               )

      assert nil ==
               SuppressKnownContracts.known_active_contract(
                 create_item(%{national_id: ""}),
                 lookup,
                 @now,
                 3
               )
    end

    test "fails open (nil) and logs when the lookup errors" do
      lookup = fn _ -> {:error, :dynamo_down} end

      log =
        capture_log(fn ->
          assert nil ==
                   SuppressKnownContracts.known_active_contract(create_item(%{}), lookup, @now, 3)
        end)

      assert log =~ "lookup failed"
    end
  end

  describe "filter_create_contracts/4" do
    test "suppresses the incident item and keeps items without a stored active contract" do
      incident = create_item(%{})
      genuine = create_item(%{national_id: "199001011234", trinity_subscriber_id: 70000})

      lookup = fn
        "195503180266" -> {:ok, [contract(%{})]}
        "199001011234" -> {:ok, []}
      end

      log =
        capture_log(fn ->
          {kept, suppressed} =
            SuppressKnownContracts.filter_create_contracts(
              %{62805 => incident, 70000 => genuine},
              lookup,
              @now
            )

          assert Map.keys(kept) == [70000]

          assert [{^incident, %CapwaySubscriber{contract_ref_no: "v2:1780472140:875617"}}] =
                   suppressed
        end)

      assert log =~ "Suppressing :capway_create_contract for subscriber 62805"
      assert log =~ "v2:1780472140:875617"
    end

    test "keeps everything when the table has no active rows" do
      items = %{1 => create_item(%{}), 2 => create_item(%{national_id: "199001011234"})}
      lookup = lookup_returning([contract(%{active: "false"})])

      assert {kept, []} = SuppressKnownContracts.filter_create_contracts(items, lookup, @now)
      assert kept == items
    end

    test "an empty map stays empty" do
      assert {%{}, []} =
               SuppressKnownContracts.filter_create_contracts(%{}, lookup_returning([]), @now)
    end
  end

  describe "run/3 result shape" do
    test "filters only actions.capway.create_contracts and leaves the rest untouched" do
      # Drive the pure filter with the same result shape run/3 rewrites.
      result = %{
        source: %{trinity: :t, capway: :c},
        actions: %{
          trinity: %{cancel_accounts: %{}, suspend_accounts: %{}},
          capway: %{
            cancel_contracts: %{"x" => :cancel},
            update_contracts: %{},
            update_customers: %{},
            create_contracts: %{62805 => create_item(%{})},
            create_mandates: %{}
          }
        }
      }

      {kept, _} =
        SuppressKnownContracts.filter_create_contracts(
          result.actions.capway.create_contracts,
          lookup_returning([contract(%{})]),
          @now
        )

      updated = put_in(result, [:actions, :capway, :create_contracts], kept)

      assert updated.actions.capway.create_contracts == %{}
      assert updated.actions.capway.cancel_contracts == %{"x" => :cancel}
      assert updated.source == result.source
    end
  end

  describe "module contract" do
    test "implements Reactor.Step and exposes the age window" do
      assert Reactor.Step in (SuppressKnownContracts.__info__(:attributes)
                              |> Keyword.get_values(:behaviour)
                              |> List.flatten())

      assert SuppressKnownContracts.max_age_days() == 3
    end
  end
end
