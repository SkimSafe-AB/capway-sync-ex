defmodule CapwaySync.Models.GeneralSyncReport do
  @moduledoc """
  Represents a comprehensive synchronization report between Trinity and Capway systems.

  This struct contains all data generated during a subscriber sync workflow execution,
  including comparison results, suspend/unsuspend analysis, and execution timing.
  """

  @typedoc """
  Collection summary showing distribution of collection values across accounts.
  Keys represent collection ranges and values are counts of accounts in each range.
  """
  @type collection_summary :: %{
          String.t() => non_neg_integer()
        }

  @typedoc """
  Unpaid invoices summary showing distribution of unpaid invoice counts.
  Keys represent invoice count ranges and values are counts of accounts in each range.
  """
  @type unpaid_invoices_summary :: %{
          String.t() => non_neg_integer()
        }

  @typedoc """
  Analysis metadata containing statistical and analytical insights.
  These fields are for reporting, analytics, and understanding trends.
  """
  @type analysis_metadata :: %{
          suspend_total_analyzed: non_neg_integer(),
          unsuspend_total_analyzed: non_neg_integer(),
          suspend_collection_summary: collection_summary(),
          unsuspend_collection_summary: collection_summary(),
          unsuspend_unpaid_invoices_summary: unpaid_invoices_summary(),
          capway: %{
            customers_with_unpaid_invoices: non_neg_integer(),
            customers_with_collections: non_neg_integer()
          }
        }

  @type t :: %__MODULE__{
          # Execution metadata
          created_at: DateTime.t() | nil,
          execution_duration_ms: non_neg_integer(),
          execution_duration_formatted: String.t(),

          # Data comparison results (actionable)
          total_trinity: non_neg_integer(),
          total_capway: non_neg_integer(),
          missing_in_capway: list(),
          missing_in_trinity: list(),
          existing_in_both: list(),
          missing_capway_count: non_neg_integer(),
          missing_trinity_count: non_neg_integer(),
          existing_in_both_count: non_neg_integer(),

          # Action results (actionable)
          suspend_accounts: list(),
          suspend_count: non_neg_integer(),
          suspend_threshold: non_neg_integer(),
          unsuspend_accounts: list(),
          unsuspend_count: non_neg_integer(),
          cancel_capway_contracts: list(),
          cancel_capway_count: non_neg_integer(),


          # Statistical and analytical insights
          analysis_metadata: analysis_metadata()
        }

  @derive Jason.Encoder
  @derive ExAws.Dynamo.Encodable
  defstruct [
    # Execution metadata
    created_at: nil,
    execution_duration_ms: 0,
    execution_duration_formatted: "0ms",

    # Data comparison results (actionable)
    total_trinity: 0,
    total_capway: 0,
    missing_in_capway: [],
    missing_in_trinity: [],
    existing_in_both: [],
    missing_capway_count: 0,
    missing_trinity_count: 0,
    existing_in_both_count: 0,

    # Action results (actionable)
    suspend_accounts: [],
    suspend_count: 0,
    suspend_threshold: 2,
    unsuspend_accounts: [],
    unsuspend_count: 0,
    cancel_capway_contracts: [],
    cancel_capway_count: 0,


    # Statistical and analytical insights
    analysis_metadata: %{
      suspend_total_analyzed: 0,
      unsuspend_total_analyzed: 0,
      suspend_collection_summary: %{},
      unsuspend_collection_summary: %{},
      unsuspend_unpaid_invoices_summary: %{},
      capway: %{
        customers_with_unpaid_invoices: 0,
        customers_with_collections: 0
      }
    }
  ]

  @doc """
  Creates a new GeneralSyncReport from workflow results.

  ## Parameters
  - `comparison_result`: Map from CompareData step
  - `suspend_result`: Map from SuspendAccounts step
  - `unsuspend_result`: Map from UnsuspendAccounts step
  - `cancel_result`: Map from CancelCapwayContracts step
  - `raw_capway_data`: Raw Capway subscriber data for detailed analysis
  - `start_time`: Start time from workflow timer
  - `end_time`: End time when report is created (default: current time)

  ## Examples

      iex> comparison_result = %{
      ...>   total_trinity: 100,
      ...>   total_capway: 95,
      ...>   missing_in_capway: [],
      ...>   missing_capway_count: 5,
      ...>   # ... other fields
      ...> }
      iex> suspend_result = %{suspend_accounts: [], suspend_count: 0, ...}
      iex> unsuspend_result = %{unsuspend_accounts: [], unsuspend_count: 0, ...}
      iex> cancel_result = %{cancel_capway_contracts: [], cancel_capway_count: 0, ...}
      iex> raw_capway_data = []
      iex> report = GeneralSyncReport.from_workflow_results(
      ...>   comparison_result,
      ...>   suspend_result,
      ...>   unsuspend_result,
      ...>   cancel_result,
      ...>   raw_capway_data,
      ...>   1000,
      ...>   1500
      ...> )
      iex> report.execution_duration_ms
      500
  """
  def from_workflow_results(
        comparison_result,
        suspend_result,
        unsuspend_result,
        cancel_result,
        raw_capway_data_or_start_time,
        start_time_or_end_time \\ nil,
        end_time \\ nil
      ) do
    # Handle backwards compatibility - if raw_capway_data_or_start_time is an integer, it's the old API
    {raw_capway_data, start_time, end_time} =
      if is_integer(raw_capway_data_or_start_time) do
        # Old API: from_workflow_results(comparison, suspend, unsuspend, cancel, start_time, end_time)
        {[], raw_capway_data_or_start_time, start_time_or_end_time}
      else
        # New API: from_workflow_results(comparison, suspend, unsuspend, cancel, raw_capway_data, start_time, end_time)
        {raw_capway_data_or_start_time, start_time_or_end_time, end_time}
      end
    end_time = end_time || System.monotonic_time(:millisecond)
    duration = end_time - start_time

    %__MODULE__{
      # Execution metadata
      created_at: DateTime.utc_now(),
      execution_duration_ms: duration,
      execution_duration_formatted: format_duration(duration),

      # Data comparison results - use ID lists for minimal storage
      total_trinity: comparison_result.total_trinity,
      total_capway: comparison_result.total_capway,
      missing_in_capway: comparison_result.missing_in_capway_ids,
      missing_in_trinity: comparison_result.missing_in_trinity_ids,
      existing_in_both: comparison_result.existing_in_both_ids,
      missing_capway_count: comparison_result.missing_capway_count,
      missing_trinity_count: comparison_result.missing_trinity_count,
      existing_in_both_count: comparison_result.existing_in_both_count,

      # Action results - extract IDs for minimal storage
      suspend_accounts: extract_subscriber_ids(suspend_result.suspend_accounts),
      suspend_count: suspend_result.suspend_count,
      suspend_threshold: suspend_result.suspend_threshold,
      unsuspend_accounts: extract_subscriber_ids(unsuspend_result.unsuspend_accounts),
      unsuspend_count: unsuspend_result.unsuspend_count,
      cancel_capway_contracts: extract_subscriber_ids(cancel_result.cancel_capway_contracts),
      cancel_capway_count: cancel_result.cancel_capway_count,

      # Statistical and analytical insights
      analysis_metadata: %{
        suspend_total_analyzed: suspend_result.total_analyzed,
        unsuspend_total_analyzed: unsuspend_result.total_analyzed,
        suspend_collection_summary: suspend_result.collection_summary,
        unsuspend_collection_summary: unsuspend_result.collection_summary,
        unsuspend_unpaid_invoices_summary: unsuspend_result.unpaid_invoices_summary,
        capway: calculate_capway_analytics(raw_capway_data || [])
      }
    }
  end

  @doc """
  Returns a summary string of the sync report for logging purposes.
  """
  def summary(%__MODULE__{} = report) do
    """
    📊 Subscriber Sync Report Summary:
    ⏱️  Execution time: #{report.execution_duration_formatted}
    📈 Data comparison:
       • Total Trinity: #{report.total_trinity}
       • Total Capway: #{report.total_capway}
       • Missing in Capway: #{report.missing_capway_count}
       • Missing in Trinity: #{report.missing_trinity_count}
       • Existing in both: #{report.existing_in_both_count}
    🔒 Suspend analysis:
       • Accounts to suspend: #{report.suspend_count}/#{report.analysis_metadata.suspend_total_analyzed} (threshold: #{report.suspend_threshold})
    🔓 Unsuspend analysis:
       • Accounts to unsuspend: #{report.unsuspend_count}/#{report.analysis_metadata.unsuspend_total_analyzed}
    🚫 Cancel analysis:
       • Capway contracts to cancel: #{report.cancel_capway_count}
    """
  end

  # Helper function to format duration in human-readable format
  defp format_duration(ms) when ms < 1000, do: "#{ms}ms"
  defp format_duration(ms) when ms < 60_000, do: "#{Float.round(ms / 1000, 2)}s"
  defp format_duration(ms) when ms < 3_600_000, do: "#{Float.round(ms / 60_000, 2)}m"
  defp format_duration(ms), do: "#{Float.round(ms / 3_600_000, 2)}h"

  # Helper function to calculate analytics from raw Capway data
  defp calculate_capway_analytics(raw_capway_data) when is_list(raw_capway_data) do
    {customers_with_unpaid_invoices, customers_with_collections} =
      Enum.reduce(raw_capway_data, {0, 0}, fn subscriber, {unpaid_acc, collection_acc} ->
        has_unpaid_invoices = has_unpaid_invoices?(subscriber)
        has_collections = has_collections?(subscriber)

        {
          if(has_unpaid_invoices, do: unpaid_acc + 1, else: unpaid_acc),
          if(has_collections, do: collection_acc + 1, else: collection_acc)
        }
      end)

    %{
      customers_with_unpaid_invoices: customers_with_unpaid_invoices,
      customers_with_collections: customers_with_collections
    }
  end

  # Check if subscriber has unpaid invoices (> 0)
  defp has_unpaid_invoices?(subscriber) do
    case Map.get(subscriber, :unpaid_invoices) do
      nil -> false
      "" -> false
      value when is_binary(value) ->
        case Integer.parse(String.trim(value)) do
          {integer_val, ""} when integer_val > 0 -> true
          _ -> false
        end
      value when is_integer(value) and value > 0 -> true
      _ -> false
    end
  end

  # Check if subscriber has collections (> 0)
  defp has_collections?(subscriber) do
    case Map.get(subscriber, :collection) do
      nil -> false
      "" -> false
      value when is_binary(value) ->
        case Integer.parse(String.trim(value)) do
          {integer_val, ""} when integer_val > 0 -> true
          _ -> false
        end
      value when is_integer(value) and value > 0 -> true
      _ -> false
    end
  end

  # Helper function to extract subscriber IDs from a list of subscriber objects
  # Prefers trinity_id, falls back to capway_id, then to other identifying fields
  defp extract_subscriber_ids(subscribers) when is_list(subscribers) do
    subscribers
    |> Enum.map(fn subscriber ->
      case subscriber do
        %{trinity_id: trinity_id} when not is_nil(trinity_id) -> trinity_id
        %{capway_id: capway_id} when not is_nil(capway_id) -> capway_id
        %{customer_ref: customer_ref} when not is_nil(customer_ref) -> customer_ref
        %{id_number: id_number} when not is_nil(id_number) -> id_number
        _ -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end
end
