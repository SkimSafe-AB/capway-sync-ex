defmodule CapwaySync.Reactor.V1.Steps.SuspendAccounts do
  @moduledoc """
  Identifies Capway accounts that should be suspended based on collection status.

  Takes accounts that exist in both Trinity and Capway systems and filters for those
  with collection >= suspend_threshold (default: 2).

  ## Return Structure

  ```elixir
  %{
    suspend_accounts: [%CapwaySubscriber{}, ...],
    suspend_count: integer(),
    suspend_threshold: integer(),
    total_analyzed: integer(),
    collection_summary: %{
      "0" => count, "1" => count, "2" => count, "3+" => count,
      "invalid" => count, "nil" => count
    }
  }
  ```

  ## Configuration

  - `suspend_threshold`: Collection value threshold for suspending (default: 2)
  """

  use Reactor.Step

  require Logger

  @default_suspend_threshold 2

  @impl Reactor.Step
  def run(arguments, _context, options \\ []) do
    Logger.info("Starting suspend accounts analysis")

    suspend_threshold = Keyword.get(options, :suspend_threshold, @default_suspend_threshold)

    with {:ok, comparison_result} <- validate_argument(arguments, :comparison_result) do
      existing_accounts = Map.get(comparison_result, :existing_in_both, [])

      result = analyze_for_suspend(existing_accounts, suspend_threshold)

      Logger.info("Suspend accounts analysis completed: #{result.suspend_count}/#{result.total_analyzed} accounts identified for suspending (threshold: #{suspend_threshold})")

      {:ok, result}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Analyzes existing accounts and identifies those that should be suspended.
  """
  def analyze_for_suspend(existing_accounts, suspend_threshold)
      when is_list(existing_accounts) and is_integer(suspend_threshold) do

    {suspend_accounts, collection_summary} =
      filter_suspend_candidates(existing_accounts, suspend_threshold)

    %{
      suspend_accounts: suspend_accounts,
      suspend_count: length(suspend_accounts),
      suspend_threshold: suspend_threshold,
      total_analyzed: length(existing_accounts),
      collection_summary: collection_summary
    }
  end

  @doc """
  Filters accounts based on collection threshold and builds summary.
  """
  def filter_suspend_candidates(accounts, suspend_threshold) when is_list(accounts) do
    initial_summary = %{"0" => 0, "1" => 0, "2" => 0, "3+" => 0, "invalid" => 0, "nil" => 0}

    Enum.reduce(accounts, {[], initial_summary}, fn account, {suspend_acc, summary_acc} ->
      case parse_collection_safely(account.collection) do
        {:ok, collection_value} when collection_value >= suspend_threshold ->
          summary_key = collection_summary_key(collection_value)
          updated_summary = Map.update(summary_acc, summary_key, 1, &(&1 + 1))
          {[account | suspend_acc], updated_summary}

        {:ok, collection_value} ->
          summary_key = collection_summary_key(collection_value)
          updated_summary = Map.update(summary_acc, summary_key, 1, &(&1 + 1))
          {suspend_acc, updated_summary}

        {:error, :nil_value} ->
          updated_summary = Map.update(summary_acc, "nil", 1, &(&1 + 1))
          {suspend_acc, updated_summary}

        {:error, :invalid_value} ->
          updated_summary = Map.update(summary_acc, "invalid", 1, &(&1 + 1))
          {suspend_acc, updated_summary}
      end
    end)
  end

  @doc """
  Safely parses collection value with idiomatic pattern matching.
  """
  def parse_collection_safely(collection) do
    case collection do
      nil -> {:error, :nil_value}
      "" -> {:error, :nil_value}
      value when is_binary(value) ->
        case Integer.parse(String.trim(value)) do
          {integer_val, ""} when integer_val >= 0 -> {:ok, integer_val}
          _ -> {:error, :invalid_value}
        end
      value when is_integer(value) and value >= 0 -> {:ok, value}
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

  defp collection_summary_key(value) when is_integer(value) do
    cond do
      value <= 1 -> "#{value}"
      value == 2 -> "2"
      value >= 3 -> "3+"
    end
  end
end