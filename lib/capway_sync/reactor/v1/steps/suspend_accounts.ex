defmodule CapwaySync.Reactor.V1.Steps.SuspendAccounts do
  @moduledoc """
  Identifies Capway accounts that should be suspended based on collection status.

  Takes accounts that exist in both Trinity and Capway systems and filters for those
  with collection >= suspend_threshold (default: 2).

  Excludes accounts with Trinity subscription status of `:pending_cancel` from suspension
  to avoid suspending accounts that are already in the cancellation process.

  ## Return Structure

  ```elixir
  %{
    suspend_accounts: [%CapwaySubscriber{}, ...],
    cancel_contracts: [%CapwaySubscriber{}, ...],
    suspend_count: integer(),
    cancel_contracts_count: integer(),
    suspend_threshold: integer(),
    total_analyzed: integer(),
    collection_summary: %{
      "0" => count, "1" => count, "2" => count, "3+" => count,
      "invalid" => count, "nil" => count
    }
  }
  ```

  Accounts that meet the suspend threshold are split into two lists:
  - `suspend_accounts`: Accounts with subscription_type == "locked" (to be suspended)
  - `cancel_contracts`: Accounts without subscription_type == "locked" (to be cancelled instead)

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

      Logger.info("Suspend accounts analysis completed: #{result.suspend_count}/#{result.total_analyzed} accounts for suspension, #{result.cancel_contracts_count} for cancellation (threshold: #{suspend_threshold})")

      {:ok, result}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Analyzes existing accounts and identifies those that should be suspended or cancelled.
  Accounts meeting the suspend threshold are split based on subscription_type:
  - "locked" subscriptions -> suspend_accounts
  - non-"locked" subscriptions -> cancel_contracts
  """
  def analyze_for_suspend(existing_accounts, suspend_threshold)
      when is_list(existing_accounts) and is_integer(suspend_threshold) do

    {suspend_accounts, cancel_contracts, collection_summary} =
      filter_suspend_candidates(existing_accounts, suspend_threshold)

    %{
      suspend_accounts: suspend_accounts,
      cancel_contracts: cancel_contracts,
      suspend_count: length(suspend_accounts),
      cancel_contracts_count: length(cancel_contracts),
      suspend_threshold: suspend_threshold,
      total_analyzed: length(existing_accounts),
      collection_summary: collection_summary
    }
  end

  @doc """
  Filters accounts based on collection threshold and builds summary.
  Excludes accounts with pending_cancel status.
  Separates accounts into suspend_accounts (locked) and cancel_contracts (non-locked).
  """
  def filter_suspend_candidates(accounts, suspend_threshold) when is_list(accounts) do
    initial_summary = %{"0" => 0, "1" => 0, "2" => 0, "3+" => 0, "invalid" => 0, "nil" => 0}
    initial_acc = {[], [], initial_summary}

    Enum.reduce(accounts, initial_acc, fn account, {suspend_acc, cancel_acc, summary_acc} ->
      # Skip accounts with pending_cancel status
      if Map.get(account, :status) == :pending_cancel do
        {suspend_acc, cancel_acc, summary_acc}
      else
        case parse_collection_safely(account.collection) do
          {:ok, collection_value} when collection_value >= suspend_threshold ->
            id = Map.get(account, :id_number) || Map.get(account, :customer_ref) || "N/A"
            name = Map.get(account, :name, "N/A")
            subscription_type = Map.get(account, :subscription_type)

            summary_key = collection_summary_key(collection_value)
            updated_summary = Map.update(summary_acc, summary_key, 1, &(&1 + 1))

            # Separate based on subscription_type
            if subscription_type == "locked" do
              Logger.debug("🔒 SUSPEND: ID #{id} | Collection: #{collection_value} | Name: #{name} | Type: locked")
              {[account | suspend_acc], cancel_acc, updated_summary}
            else
              Logger.debug("🚫 CANCEL: ID #{id} | Collection: #{collection_value} | Name: #{name} | Type: #{subscription_type || "nil"}")
              {suspend_acc, [account | cancel_acc], updated_summary}
            end

          {:ok, collection_value} ->
            summary_key = collection_summary_key(collection_value)
            updated_summary = Map.update(summary_acc, summary_key, 1, &(&1 + 1))
            {suspend_acc, cancel_acc, updated_summary}

          {:error, :nil_value} ->
            updated_summary = Map.update(summary_acc, "nil", 1, &(&1 + 1))
            {suspend_acc, cancel_acc, updated_summary}

          {:error, :invalid_value} ->
            updated_summary = Map.update(summary_acc, "invalid", 1, &(&1 + 1))
            {suspend_acc, cancel_acc, updated_summary}
        end
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