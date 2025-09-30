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

  @type t :: %__MODULE__{
          # Execution metadata
          created_at: DateTime.t() | nil,
          execution_duration_ms: non_neg_integer(),
          execution_duration_formatted: String.t(),

          # Data comparison results
          total_trinity: non_neg_integer(),
          total_capway: non_neg_integer(),
          missing_in_capway: list(),
          missing_in_trinity: list(),
          existing_in_both: list(),
          missing_capway_count: non_neg_integer(),
          missing_trinity_count: non_neg_integer(),
          existing_in_both_count: non_neg_integer(),

          # Suspend accounts analysis
          suspend_accounts: list(),
          suspend_count: non_neg_integer(),
          suspend_threshold: non_neg_integer(),
          suspend_total_analyzed: non_neg_integer(),
          suspend_collection_summary: collection_summary(),

          # Unsuspend accounts analysis
          unsuspend_accounts: list(),
          unsuspend_count: non_neg_integer(),
          unsuspend_total_analyzed: non_neg_integer(),
          unsuspend_collection_summary: collection_summary(),
          unsuspend_unpaid_invoices_summary: unpaid_invoices_summary()
        }

  @derive Jason.Encoder
  defstruct [
    # Execution metadata
    created_at: nil,
    execution_duration_ms: 0,
    execution_duration_formatted: "0ms",

    # Data comparison results
    total_trinity: 0,
    total_capway: 0,
    missing_in_capway: [],
    missing_in_trinity: [],
    existing_in_both: [],
    missing_capway_count: 0,
    missing_trinity_count: 0,
    existing_in_both_count: 0,

    # Suspend accounts analysis
    suspend_accounts: [],
    suspend_count: 0,
    suspend_threshold: 2,
    suspend_total_analyzed: 0,
    suspend_collection_summary: %{},

    # Unsuspend accounts analysis
    unsuspend_accounts: [],
    unsuspend_count: 0,
    unsuspend_total_analyzed: 0,
    unsuspend_collection_summary: %{},
    unsuspend_unpaid_invoices_summary: %{}
  ]

  @doc """
  Creates a new GeneralSyncReport from workflow results.

  ## Parameters
  - `comparison_result`: Map from CompareData step
  - `suspend_result`: Map from SuspendAccounts step
  - `unsuspend_result`: Map from UnsuspendAccounts step
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
      iex> report = GeneralSyncReport.from_workflow_results(
      ...>   comparison_result,
      ...>   suspend_result,
      ...>   unsuspend_result,
      ...>   1000,
      ...>   1500
      ...> )
      iex> report.execution_duration_ms
      500
  """
  def from_workflow_results(comparison_result, suspend_result, unsuspend_result, start_time, end_time \\ nil) do
    end_time = end_time || System.monotonic_time(:millisecond)
    duration = end_time - start_time

    %__MODULE__{
      # Execution metadata
      created_at: DateTime.utc_now(),
      execution_duration_ms: duration,
      execution_duration_formatted: format_duration(duration),

      # Data comparison results
      total_trinity: comparison_result.total_trinity,
      total_capway: comparison_result.total_capway,
      missing_in_capway: comparison_result.missing_in_capway,
      missing_in_trinity: comparison_result.missing_in_trinity,
      existing_in_both: comparison_result.existing_in_both,
      missing_capway_count: comparison_result.missing_capway_count,
      missing_trinity_count: comparison_result.missing_trinity_count,
      existing_in_both_count: comparison_result.existing_in_both_count,

      # Suspend accounts analysis
      suspend_accounts: suspend_result.suspend_accounts,
      suspend_count: suspend_result.suspend_count,
      suspend_threshold: suspend_result.suspend_threshold,
      suspend_total_analyzed: suspend_result.total_analyzed,
      suspend_collection_summary: suspend_result.collection_summary,

      # Unsuspend accounts analysis
      unsuspend_accounts: unsuspend_result.unsuspend_accounts,
      unsuspend_count: unsuspend_result.unsuspend_count,
      unsuspend_total_analyzed: unsuspend_result.total_analyzed,
      unsuspend_collection_summary: unsuspend_result.collection_summary,
      unsuspend_unpaid_invoices_summary: unsuspend_result.unpaid_invoices_summary
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
       • Accounts to suspend: #{report.suspend_count}/#{report.suspend_total_analyzed} (threshold: #{report.suspend_threshold})
    🔓 Unsuspend analysis:
       • Accounts to unsuspend: #{report.unsuspend_count}/#{report.unsuspend_total_analyzed}
    """
  end

  # Helper function to format duration in human-readable format
  defp format_duration(ms) when ms < 1000, do: "#{ms}ms"
  defp format_duration(ms) when ms < 60_000, do: "#{Float.round(ms / 1000, 2)}s"
  defp format_duration(ms) when ms < 3_600_000, do: "#{Float.round(ms / 60_000, 2)}m"
  defp format_duration(ms), do: "#{Float.round(ms / 3_600_000, 2)}h"
end
