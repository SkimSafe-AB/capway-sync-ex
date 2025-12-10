defmodule CapwaySync.Reactor.V1.Steps.UnsuspendAccountsTest do
  use ExUnit.Case
  alias CapwaySync.Reactor.V1.Steps.UnsuspendAccounts

  describe "run/3 - main Reactor step interface" do
    test "identifies accounts for unsuspending based on collection and unpaid_invoices = 0" do
      comparison_result = %{
        existing_in_both: [
          %{customer_ref: "100", name: "Alice", collection: "1", unpaid_invoices: "0"},
          %{customer_ref: "200", name: "Bob", collection: "0", unpaid_invoices: "0"},
          %{customer_ref: "300", name: "Charlie", collection: "0", unpaid_invoices: "1"},
          %{customer_ref: "400", name: "David", collection: "2", unpaid_invoices: "0"}
        ]
      }

      arguments = %{comparison_result: comparison_result}

      assert {:ok, result} = UnsuspendAccounts.run(arguments, %{})

      # Only Bob (collection: 0, unpaid_invoices: 0) should be unsuspended
      assert result.unsuspend_count == 1
      assert result.total_analyzed == 4

      unsuspend_refs = Enum.map(result.unsuspend_accounts, & &1.customer_ref)
      assert "200" in unsuspend_refs
      refute "100" in unsuspend_refs
      refute "300" in unsuspend_refs
      refute "400" in unsuspend_refs

      # Verify collection summary
      # Bob and Charlie
      assert result.collection_summary["0"] == 2
      # Alice
      assert result.collection_summary["1"] == 1
      # David
      assert result.collection_summary["2"] == 1

      # Verify unpaid_invoices summary
      # Alice, Bob, David
      assert result.unpaid_invoices_summary["0"] == 3
      # Charlie
      assert result.unpaid_invoices_summary["1"] == 1
    end

    test "handles empty existing_in_both list" do
      comparison_result = %{existing_in_both: []}
      arguments = %{comparison_result: comparison_result}

      assert {:ok, result} = UnsuspendAccounts.run(arguments, %{})

      assert result.unsuspend_count == 0
      assert result.total_analyzed == 0
      assert result.unsuspend_accounts == []
    end

    test "returns error for missing comparison_result" do
      arguments = %{}

      assert {:error, "Missing required argument: comparison_result"} =
               UnsuspendAccounts.run(arguments, %{})
    end

    test "returns error for invalid comparison_result format" do
      arguments = %{comparison_result: %{some_other_key: "value"}}

      assert {:error, "Invalid comparison_result format - missing existing_in_both"} =
               UnsuspendAccounts.run(arguments, %{})
    end
  end

  describe "analyze_for_unsuspend/1" do
    test "analyzes accounts and returns structured result" do
      existing_accounts = [
        %{customer_ref: "100", collection: "0", unpaid_invoices: "0"},
        %{customer_ref: "200", collection: "0", unpaid_invoices: "1"},
        %{customer_ref: "300", collection: "1", unpaid_invoices: "0"}
      ]

      result = UnsuspendAccounts.analyze_for_unsuspend(existing_accounts)

      assert result.unsuspend_count == 1
      assert result.total_analyzed == 3

      unsuspend_refs = Enum.map(result.unsuspend_accounts, & &1.customer_ref)
      assert "100" in unsuspend_refs
      refute "200" in unsuspend_refs
      refute "300" in unsuspend_refs
    end
  end

  describe "filter_unsuspend_candidates/1" do
    test "filters accounts where both collection and unpaid_invoices are 0" do
      accounts = [
        %{customer_ref: "100", collection: "0", unpaid_invoices: "0"},
        %{customer_ref: "200", collection: "0", unpaid_invoices: "1"},
        %{customer_ref: "300", collection: "1", unpaid_invoices: "0"},
        %{customer_ref: "400", collection: "0", unpaid_invoices: "0"},
        %{customer_ref: "500", collection: "2", unpaid_invoices: "3"}
      ]

      {unsuspend_accounts, collection_summary, unpaid_summary} =
        UnsuspendAccounts.filter_unsuspend_candidates(accounts)

      assert length(unsuspend_accounts) == 2
      unsuspend_refs = Enum.map(unsuspend_accounts, & &1.customer_ref)
      assert "100" in unsuspend_refs
      assert "400" in unsuspend_refs
      refute "200" in unsuspend_refs
      refute "300" in unsuspend_refs
      refute "500" in unsuspend_refs

      # Collection summary
      # 100, 200, 400
      assert collection_summary["0"] == 3
      # 300
      assert collection_summary["1"] == 1
      # 500
      assert collection_summary["2"] == 1

      # Unpaid invoices summary
      # 100, 300, 400
      assert unpaid_summary["0"] == 3
      # 200
      assert unpaid_summary["1"] == 1
      # 500
      assert unpaid_summary["3+"] == 1
    end

    test "handles nil and invalid values" do
      accounts = [
        %{customer_ref: "100", collection: nil, unpaid_invoices: "0"},
        %{customer_ref: "200", collection: "0", unpaid_invoices: nil},
        %{customer_ref: "300", collection: "", unpaid_invoices: ""},
        %{customer_ref: "400", collection: "invalid", unpaid_invoices: "2.5"},
        %{customer_ref: "500", collection: "0", unpaid_invoices: "0"}
      ]

      {unsuspend_accounts, collection_summary, unpaid_summary} =
        UnsuspendAccounts.filter_unsuspend_candidates(accounts)

      # Only account 500 should qualify (both values are valid 0s)
      assert length(unsuspend_accounts) == 1
      assert hd(unsuspend_accounts).customer_ref == "500"

      # Collection summary
      # nil and ""
      assert collection_summary["nil"] == 2
      # "invalid"
      assert collection_summary["invalid"] == 1
      # 200, 500
      assert collection_summary["0"] == 2

      # Unpaid invoices summary
      # nil and ""
      assert unpaid_summary["nil"] == 2
      # "2.5"
      assert unpaid_summary["invalid"] == 1
      # 100, 500
      assert unpaid_summary["0"] == 2
    end

    test "handles integer values" do
      accounts = [
        %{customer_ref: "100", collection: 0, unpaid_invoices: 0},
        %{customer_ref: "200", collection: 0, unpaid_invoices: 1},
        %{customer_ref: "300", collection: 1, unpaid_invoices: 0}
      ]

      {unsuspend_accounts, collection_summary, unpaid_summary} =
        UnsuspendAccounts.filter_unsuspend_candidates(accounts)

      assert length(unsuspend_accounts) == 1
      assert hd(unsuspend_accounts).customer_ref == "100"

      # 100, 200
      assert collection_summary["0"] == 2
      # 300
      assert collection_summary["1"] == 1

      # 100, 300
      assert unpaid_summary["0"] == 2
      # 200
      assert unpaid_summary["1"] == 1
    end

    test "requires both collection AND unpaid_invoices to be 0" do
      accounts = [
        # Only collection is 0
        %{customer_ref: "100", collection: "0", unpaid_invoices: "1"},
        # Only unpaid_invoices is 0
        %{customer_ref: "200", collection: "1", unpaid_invoices: "0"},
        # Both are 0
        %{customer_ref: "300", collection: "0", unpaid_invoices: "0"}
      ]

      {unsuspend_accounts, _collection_summary, _unpaid_summary} =
        UnsuspendAccounts.filter_unsuspend_candidates(accounts)

      assert length(unsuspend_accounts) == 1
      assert hd(unsuspend_accounts).customer_ref == "300"
    end
  end

  describe "parse_value_safely/1" do
    test "parses valid string numbers" do
      assert {:ok, 0} = UnsuspendAccounts.parse_value_safely("0")
      assert {:ok, 1} = UnsuspendAccounts.parse_value_safely("1")
      assert {:ok, 5} = UnsuspendAccounts.parse_value_safely("5")
      # with whitespace
      assert {:ok, 10} = UnsuspendAccounts.parse_value_safely(" 10 ")
    end

    test "handles valid integers" do
      assert {:ok, 0} = UnsuspendAccounts.parse_value_safely(0)
      assert {:ok, 2} = UnsuspendAccounts.parse_value_safely(2)
      assert {:ok, 100} = UnsuspendAccounts.parse_value_safely(100)
    end

    test "handles nil and empty values" do
      assert {:error, :nil_value} = UnsuspendAccounts.parse_value_safely(nil)
      assert {:error, :nil_value} = UnsuspendAccounts.parse_value_safely("")
    end

    test "handles invalid values" do
      assert {:error, :invalid_value} = UnsuspendAccounts.parse_value_safely("abc")
      assert {:error, :invalid_value} = UnsuspendAccounts.parse_value_safely("2.5")
      assert {:error, :invalid_value} = UnsuspendAccounts.parse_value_safely("2extra")
      assert {:error, :invalid_value} = UnsuspendAccounts.parse_value_safely(-1)
      assert {:error, :invalid_value} = UnsuspendAccounts.parse_value_safely(-5)
    end

    test "handles edge cases" do
      assert {:error, :invalid_value} = UnsuspendAccounts.parse_value_safely(%{})
      assert {:error, :invalid_value} = UnsuspendAccounts.parse_value_safely([])
      assert {:error, :invalid_value} = UnsuspendAccounts.parse_value_safely(:atom)
    end
  end
end
