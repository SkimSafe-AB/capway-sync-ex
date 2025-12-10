defmodule CapwaySync.Reactor.V1.Steps.SuspendAccountsTest do
  use ExUnit.Case
  alias CapwaySync.Reactor.V1.Steps.SuspendAccounts

  describe "run/3 - main Reactor step interface" do
    test "identifies accounts for suspending based on collection threshold and subscription_type" do
      comparison_result = %{
        existing_in_both: [
          %{customer_ref: "100", name: "Alice", collection: "1", subscription_type: nil},
          %{customer_ref: "200", name: "Bob", collection: "2", subscription_type: "locked"},
          %{customer_ref: "300", name: "Charlie", collection: "3", subscription_type: nil},
          %{customer_ref: "400", name: "David", collection: "0", subscription_type: nil}
        ]
      }

      arguments = %{comparison_result: comparison_result}

      assert {:ok, result} = SuspendAccounts.run(arguments, %{})

      # Bob (locked, collection: 2) should be suspended
      assert result.suspend_count == 1
      # Charlie (not locked, collection: 3) should be in cancel_contracts
      assert result.cancel_contracts_count == 1
      assert result.total_analyzed == 4
      assert result.suspend_threshold == 2

      suspend_refs = Enum.map(result.suspend_accounts, & &1.customer_ref)
      # Bob - locked
      assert "200" in suspend_refs
      # Charlie - not locked
      refute "300" in suspend_refs

      cancel_refs = Enum.map(result.cancel_contracts, & &1.customer_ref)
      # Charlie - not locked
      assert "300" in cancel_refs
      # Bob - locked
      refute "200" in cancel_refs

      refute "100" in suspend_refs
      refute "400" in suspend_refs

      # Verify collection summary
      assert result.collection_summary["0"] == 1
      assert result.collection_summary["1"] == 1
      assert result.collection_summary["2"] == 1
      assert result.collection_summary["3+"] == 1
    end

    test "supports custom suspend threshold" do
      comparison_result = %{
        existing_in_both: [
          %{customer_ref: "100", collection: "2", subscription_type: nil},
          %{customer_ref: "200", collection: "3", subscription_type: "locked"}
        ]
      }

      arguments = %{comparison_result: comparison_result}
      options = [suspend_threshold: 3]

      assert {:ok, result} = SuspendAccounts.run(arguments, %{}, options)

      # Only collection >= 3 and locked should be suspended
      assert result.suspend_count == 1
      assert result.cancel_contracts_count == 0
      assert result.suspend_threshold == 3

      suspend_refs = Enum.map(result.suspend_accounts, & &1.customer_ref)
      # locked
      assert "200" in suspend_refs
      # below threshold
      refute "100" in suspend_refs
    end

    test "handles empty existing_in_both list" do
      comparison_result = %{existing_in_both: []}
      arguments = %{comparison_result: comparison_result}

      assert {:ok, result} = SuspendAccounts.run(arguments, %{})

      assert result.suspend_count == 0
      assert result.total_analyzed == 0
      assert result.suspend_accounts == []
    end

    test "returns error for missing comparison_result" do
      arguments = %{}

      assert {:error, "Missing required argument: comparison_result"} =
               SuspendAccounts.run(arguments, %{})
    end

    test "returns error for invalid comparison_result format" do
      arguments = %{comparison_result: %{some_other_key: "value"}}

      assert {:error, "Invalid comparison_result format - missing existing_in_both"} =
               SuspendAccounts.run(arguments, %{})
    end

    test "excludes accounts with pending_cancel status from suspension" do
      comparison_result = %{
        existing_in_both: [
          %{
            customer_ref: "100",
            name: "Alice",
            collection: "3",
            status: :active,
            subscription_type: "locked"
          },
          %{
            customer_ref: "200",
            name: "Bob",
            collection: "4",
            status: :pending_cancel,
            subscription_type: "locked"
          },
          %{
            customer_ref: "300",
            name: "Charlie",
            collection: "5",
            status: :cancelled,
            subscription_type: nil
          },
          %{
            customer_ref: "400",
            name: "David",
            collection: "2",
            status: nil,
            subscription_type: "locked"
          }
        ]
      }

      arguments = %{comparison_result: comparison_result}

      assert {:ok, result} = SuspendAccounts.run(arguments, %{})

      # Alice (locked, active, collection: 3) and David (locked, nil status, collection: 2) should be suspended
      # Charlie (not locked, cancelled, collection: 5) should be in cancel_contracts
      # Bob (pending_cancel) should be excluded entirely
      assert result.suspend_count == 2
      assert result.cancel_contracts_count == 1
      assert result.total_analyzed == 4

      suspend_refs = Enum.map(result.suspend_accounts, & &1.customer_ref)
      # Alice - locked, active status
      assert "100" in suspend_refs
      # David - locked, nil status
      assert "400" in suspend_refs
      # Bob - pending_cancel should be excluded
      refute "200" in suspend_refs

      cancel_refs = Enum.map(result.cancel_contracts, & &1.customer_ref)
      # Charlie - not locked
      assert "300" in cancel_refs
      # Bob - pending_cancel should be excluded
      refute "200" in cancel_refs
    end
  end

  describe "analyze_for_suspend/2" do
    test "analyzes accounts and returns structured result with subscription_type separation" do
      existing_accounts = [
        %{customer_ref: "100", collection: "1", subscription_type: nil},
        %{customer_ref: "200", collection: "2", subscription_type: "locked"},
        %{customer_ref: "300", collection: "4", subscription_type: nil}
      ]

      result = SuspendAccounts.analyze_for_suspend(existing_accounts, 2)

      # Only locked account should be in suspend_accounts
      assert result.suspend_count == 1
      # Non-locked account should be in cancel_contracts
      assert result.cancel_contracts_count == 1
      assert result.total_analyzed == 3
      assert result.suspend_threshold == 2

      suspend_refs = Enum.map(result.suspend_accounts, & &1.customer_ref)
      # locked
      assert "200" in suspend_refs

      cancel_refs = Enum.map(result.cancel_contracts, & &1.customer_ref)
      # not locked
      assert "300" in cancel_refs
    end
  end

  describe "filter_suspend_candidates/2" do
    test "filters accounts by collection threshold and separates locked from non-locked" do
      accounts = [
        %{customer_ref: "100", collection: "0", subscription_type: nil},
        %{customer_ref: "200", collection: "1", subscription_type: nil},
        %{customer_ref: "300", collection: "2", subscription_type: "locked"},
        %{customer_ref: "400", collection: "3", subscription_type: nil},
        %{customer_ref: "500", collection: "5", subscription_type: "locked"}
      ]

      {suspend_accounts, cancel_contracts, summary} =
        SuspendAccounts.filter_suspend_candidates(accounts, 2)

      # Only locked subscriptions go to suspend_accounts
      assert length(suspend_accounts) == 2
      suspend_refs = Enum.map(suspend_accounts, & &1.customer_ref)
      # locked
      assert "300" in suspend_refs
      # locked
      assert "500" in suspend_refs

      # Non-locked subscriptions go to cancel_contracts
      assert length(cancel_contracts) == 1
      cancel_refs = Enum.map(cancel_contracts, & &1.customer_ref)
      # non-locked
      assert "400" in cancel_refs

      assert summary["0"] == 1
      assert summary["1"] == 1
      assert summary["2"] == 1
      assert summary["3+"] == 2
    end

    test "handles nil and invalid collection values" do
      accounts = [
        %{customer_ref: "100", collection: nil, subscription_type: nil},
        %{customer_ref: "200", collection: "", subscription_type: nil},
        %{customer_ref: "300", collection: "invalid", subscription_type: nil},
        %{customer_ref: "400", collection: "2.5", subscription_type: nil},
        %{customer_ref: "500", collection: "2", subscription_type: "locked"}
      ]

      {suspend_accounts, cancel_contracts, summary} =
        SuspendAccounts.filter_suspend_candidates(accounts, 2)

      # Only the locked account with collection "2" should be in suspend_accounts
      assert length(suspend_accounts) == 1
      assert hd(suspend_accounts).customer_ref == "500"
      assert length(cancel_contracts) == 0

      # nil and ""
      assert summary["nil"] == 2
      # "invalid" and "2.5"
      assert summary["invalid"] == 2
      assert summary["2"] == 1
    end

    test "handles integer collection values" do
      accounts = [
        %{customer_ref: "100", collection: 1, subscription_type: nil},
        %{customer_ref: "200", collection: 2, subscription_type: "locked"},
        %{customer_ref: "300", collection: 3, subscription_type: nil}
      ]

      {suspend_accounts, cancel_contracts, summary} =
        SuspendAccounts.filter_suspend_candidates(accounts, 2)

      # Only locked account goes to suspend_accounts
      assert length(suspend_accounts) == 1
      suspend_refs = Enum.map(suspend_accounts, & &1.customer_ref)
      assert "200" in suspend_refs

      # Non-locked account goes to cancel_contracts
      assert length(cancel_contracts) == 1
      cancel_refs = Enum.map(cancel_contracts, & &1.customer_ref)
      assert "300" in cancel_refs

      assert summary["1"] == 1
      assert summary["2"] == 1
      assert summary["3+"] == 1
    end
  end

  describe "parse_collection_safely/1" do
    test "parses valid string numbers" do
      assert {:ok, 0} = SuspendAccounts.parse_collection_safely("0")
      assert {:ok, 1} = SuspendAccounts.parse_collection_safely("1")
      assert {:ok, 5} = SuspendAccounts.parse_collection_safely("5")
      # with whitespace
      assert {:ok, 10} = SuspendAccounts.parse_collection_safely(" 10 ")
    end

    test "handles valid integers" do
      assert {:ok, 0} = SuspendAccounts.parse_collection_safely(0)
      assert {:ok, 2} = SuspendAccounts.parse_collection_safely(2)
      assert {:ok, 100} = SuspendAccounts.parse_collection_safely(100)
    end

    test "handles nil and empty values" do
      assert {:error, :nil_value} = SuspendAccounts.parse_collection_safely(nil)
      assert {:error, :nil_value} = SuspendAccounts.parse_collection_safely("")
    end

    test "handles invalid values" do
      assert {:error, :invalid_value} = SuspendAccounts.parse_collection_safely("abc")
      assert {:error, :invalid_value} = SuspendAccounts.parse_collection_safely("2.5")
      assert {:error, :invalid_value} = SuspendAccounts.parse_collection_safely("2extra")
      assert {:error, :invalid_value} = SuspendAccounts.parse_collection_safely(-1)
      assert {:error, :invalid_value} = SuspendAccounts.parse_collection_safely(-5)
    end

    test "handles edge cases" do
      assert {:error, :invalid_value} = SuspendAccounts.parse_collection_safely(%{})
      assert {:error, :invalid_value} = SuspendAccounts.parse_collection_safely([])
      assert {:error, :invalid_value} = SuspendAccounts.parse_collection_safely(:atom)
    end
  end
end
