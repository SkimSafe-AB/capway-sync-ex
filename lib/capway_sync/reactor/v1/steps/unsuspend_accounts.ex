defmodule CapwaySync.Reactor.V1.Steps.UnsuspendAccounts do
  @moduledoc """
  Identifies Capway accounts that should be unsuspended based on collection and invoice status.

  Takes accounts that exist in both Trinity and Capway systems and filters for those
  with collection = 0 AND unpaid_invoices = 0.

  ## Return Structure

  ```elixir
  %{
    unsuspend_accounts: [%CapwaySubscriber{}, ...],
    unsuspend_count: integer(),
    total_analyzed: integer(),
    collection_summary: %{
      "0" => count, "1" => count, "2" => count, "3+" => count,
      "invalid" => count, "nil" => count
    },
    unpaid_invoices_summary: %{
      "0" => count, "1" => count, "2" => count, "3+" => count,
      "invalid" => count, "nil" => count
    }
  }
  ```

  ## Logic

  An account qualifies for unsuspending if:
  - collection = 0 (exactly zero)
  - unpaid_invoices = 0 (exactly zero)
  """

  use Reactor.Step

  require Logger

  @impl Reactor.Step
  def run(arguments, _context, _options \\ []) do
    Logger.info("Starting unsuspend accounts analysis")

    with {:ok, comparison_result} <- validate_argument(arguments, :comparison_result) do
      existing_accounts = Map.get(comparison_result, :existing_in_both, [])

      result = analyze_for_unsuspend(existing_accounts)

      Logger.info("Unsuspend accounts analysis completed: #{result.unsuspend_count}/#{result.total_analyzed} accounts identified for unsuspending")

      {:ok, result}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Analyzes existing accounts and identifies those that should be unsuspended.
  """
  def analyze_for_unsuspend(existing_accounts) when is_list(existing_accounts) do
    {unsuspend_accounts, collection_summary, unpaid_invoices_summary} =
      filter_unsuspend_candidates(existing_accounts)

    %{
      unsuspend_accounts: unsuspend_accounts,
      unsuspend_count: length(unsuspend_accounts),
      total_analyzed: length(existing_accounts),
      collection_summary: collection_summary,
      unpaid_invoices_summary: unpaid_invoices_summary
    }
  end

  @doc """
  Filters accounts that qualify for unsuspending and builds summaries.
  """
  def filter_unsuspend_candidates(accounts) when is_list(accounts) do
    initial_summary = %{"0" => 0, "1" => 0, "2" => 0, "3+" => 0, "invalid" => 0, "nil" => 0}

    Enum.reduce(accounts, {[], initial_summary, initial_summary}, fn account, {unsuspend_acc, collection_summary_acc, unpaid_summary_acc} ->
      collection_result = parse_value_safely(account.collection)
      unpaid_result = parse_value_safely(account.unpaid_invoices)

      # Update collection summary
      collection_key = summary_key_for_result(collection_result)
      updated_collection_summary = Map.update(collection_summary_acc, collection_key, 1, &(&1 + 1))

      # Update unpaid invoices summary
      unpaid_key = summary_key_for_result(unpaid_result)
      updated_unpaid_summary = Map.update(unpaid_summary_acc, unpaid_key, 1, &(&1 + 1))

      # Check if account qualifies for unsuspending (both collection and unpaid_invoices must be 0)
      case {collection_result, unpaid_result} do
        {{:ok, 0}, {:ok, 0}} ->
          {[account | unsuspend_acc], updated_collection_summary, updated_unpaid_summary}

        _ ->
          {unsuspend_acc, updated_collection_summary, updated_unpaid_summary}
      end
    end)
  end

  @doc """
  Safely parses a value with idiomatic pattern matching.
  """
  def parse_value_safely(value) do
    case value do
      nil -> {:error, :nil_value}
      "" -> {:error, :nil_value}
      val when is_binary(val) ->
        case Integer.parse(String.trim(val)) do
          {integer_val, ""} when integer_val >= 0 -> {:ok, integer_val}
          _ -> {:error, :invalid_value}
        end
      val when is_integer(val) and val >= 0 -> {:ok, val}
      _ -> {:error, :invalid_value}
    end
  end

  # Private helper functions

  defp validate_argument(arguments, key) do
    case Map.get(arguments, key) do
      nil -> {:error, "Missing required argument: #{key}"}
      %{existing_in_both: _} = value -> {:ok, value}
      _ -> {:error, "Invalid comparison_result format - missing existing_in_both"}
    end
  end

  defp summary_key_for_result(result) do
    case result do
      {:ok, value} -> value_summary_key(value)
      {:error, :nil_value} -> "nil"
      {:error, :invalid_value} -> "invalid"
    end
  end

  defp value_summary_key(value) when is_integer(value) do
    cond do
      value <= 1 -> "#{value}"
      value == 2 -> "2"
      value >= 3 -> "3+"
    end
  end

end