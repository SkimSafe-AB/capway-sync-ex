defmodule CapwaySync.Dynamodb.GeneralSyncReportRepository do
  @moduledoc """
  Repository module for storing and retrieving GeneralSyncReport records in DynamoDB.

  This module handles the serialization, storage, and retrieval of GeneralSyncReport
  structs to/from a DynamoDB table. It manages the conversion between Elixir structs
  and DynamoDB-compatible data formats.

  ## Configuration

  The DynamoDB table name can be configured via environment variables or application config:
  - `SYNC_REPORTS_TABLE` environment variable
  - Application config: `config :capway_sync, sync_reports_table: "sync-reports"`

  ## Table Schema

  The DynamoDB table should have the following structure:
  - **Partition Key**: `report_id` (String) - UUID of the report
  - **Sort Key**: `created_at` (String) - ISO8601 timestamp for ordering
  - **Attributes**: All GeneralSyncReport fields stored as DynamoDB-compatible types

  ## Usage

      # Store a report
      {:ok, report_id} = GeneralSyncReportRepository.store_report(report)

      # Retrieve a specific report
      {:ok, report} = GeneralSyncReportRepository.get_report(report_id, created_at)

      # Query recent reports
      {:ok, reports} = GeneralSyncReportRepository.list_recent_reports(limit: 10)
  """

  alias CapwaySync.Models.GeneralSyncReport
  alias CapwaySync.Dynamodb.Client

  require Logger

  @table_name_env "SYNC_REPORTS_TABLE"
  @default_table_name "capway-sync-reports"

  @doc """
  Stores a GeneralSyncReport to DynamoDB.

  Automatically generates a UUID for the report and uses the created_at timestamp
  as the sort key. The report is serialized to DynamoDB-compatible format.

  ## Parameters
  - `report`: %GeneralSyncReport{} struct to store

  ## Returns
  - `{:ok, report_id}` on success - returns the generated UUID for the report
  - `{:error, reason}` on failure

  ## Examples

      iex> report = %GeneralSyncReport{total_trinity: 100, total_capway: 95, ...}
      iex> {:ok, report_id} = GeneralSyncReportRepository.store_report(report)
      iex> is_binary(report_id)
      true
  """
  def store_report(%GeneralSyncReport{} = report) do
    report_id = UUID.uuid4()
    table_name = get_table_name()

    # Ensure created_at is set
    report = %{report | created_at: report.created_at || DateTime.utc_now()}

    # Convert to DynamoDB item format
    dynamodb_item = struct_to_dynamodb_item(report, report_id)

    Logger.info(
      "Storing GeneralSyncReport to DynamoDB table: #{table_name}, report_id: #{report_id}"
    )

    case Client.put_item(table_name, dynamodb_item) do
      {:ok, _result} ->
        Logger.info("Successfully stored GeneralSyncReport with ID: #{report_id}")
        {:ok, report_id}

      {:error, reason} = error ->
        Logger.error("Failed to store GeneralSyncReport: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Retrieves a GeneralSyncReport from DynamoDB by report_id and created_at.

  ## Parameters
  - `report_id`: UUID string of the report
  - `created_at`: DateTime or ISO8601 string of when the report was created

  ## Returns
  - `{:ok, %GeneralSyncReport{}}` on success
  - `{:ok, nil}` if report not found
  - `{:error, reason}` on failure
  """
  def get_report(report_id, created_at) when is_binary(report_id) do
    table_name = get_table_name()
    created_at_str = format_datetime_for_dynamodb(created_at)

    key = %{
      "report_id" => report_id,
      "created_at" => created_at_str
    }

    Logger.debug("Retrieving GeneralSyncReport from #{table_name} with key: #{inspect(key)}")

    case Client.get_item(table_name, key) do
      {:ok, %{"Item" => item}} when map_size(item) > 0 ->
        report = dynamodb_item_to_struct(item)
        {:ok, report}

      {:ok, _empty_result} ->
        Logger.debug("GeneralSyncReport not found for report_id: #{report_id}")
        {:ok, nil}

      {:error, reason} = error ->
        Logger.error("Failed to retrieve GeneralSyncReport: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Lists recent GeneralSyncReport records from DynamoDB.

  Uses a scan operation to retrieve the most recent reports across all partitions.
  For production use, consider implementing a GSI for more efficient querying.

  ## Parameters
  - `opts`: Keyword list of options
    - `:limit` - Maximum number of reports to return (default: 50)
    - `:start_date` - Only return reports after this date (DateTime)
    - `:end_date` - Only return reports before this date (DateTime)

  ## Returns
  - `{:ok, [%GeneralSyncReport{}]}` on success
  - `{:error, reason}` on failure
  """
  def list_recent_reports(opts \\ []) do
    table_name = get_table_name()
    limit = Keyword.get(opts, :limit, 50)

    # For now, use scan. In production, implement GSI for better performance
    scan_params = %{
      "TableName" => table_name,
      "Limit" => limit
    }

    scan_params = maybe_add_date_filters(scan_params, opts)

    Logger.debug(
      "Scanning GeneralSyncReport table: #{table_name} with params: #{inspect(scan_params)}"
    )

    case ExAws.Dynamo.scan(scan_params) |> ExAws.request() do
      {:ok, %{"Items" => items}} ->
        reports = Enum.map(items, &dynamodb_item_to_struct/1)
        # Sort by created_at descending
        reports = Enum.sort_by(reports, & &1.created_at, {:desc, DateTime})
        {:ok, reports}

      {:error, reason} = error ->
        Logger.error("Failed to scan GeneralSyncReport table: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Deletes a GeneralSyncReport from DynamoDB.

  ## Parameters
  - `report_id`: UUID string of the report to delete
  - `created_at`: DateTime or ISO8601 string of when the report was created

  ## Returns
  - `{:ok, :deleted}` on success
  - `{:error, reason}` on failure
  """
  def delete_report(report_id, created_at) when is_binary(report_id) do
    table_name = get_table_name()
    created_at_str = format_datetime_for_dynamodb(created_at)

    key = %{
      "report_id" => report_id,
      "created_at" => created_at_str
    }

    Logger.info("Deleting GeneralSyncReport from #{table_name} with key: #{inspect(key)}")

    case Client.delete_item(table_name, key) do
      {:ok, _result} ->
        Logger.info("Successfully deleted GeneralSyncReport with ID: #{report_id}")
        {:ok, :deleted}

      {:error, reason} = error ->
        Logger.error("Failed to delete GeneralSyncReport: #{inspect(reason)}")
        error
    end
  end

  # Private helper functions

  defp get_table_name do
    System.get_env(@table_name_env) ||
      Application.get_env(:capway_sync, :sync_reports_table) ||
      @default_table_name
  end

  defp struct_to_dynamodb_item(%GeneralSyncReport{} = report, report_id) do
    %{
      # Primary keys
      "id" => report_id,
      "date" => format_date_for_dynamodb(report.created_at),
      "created_at" => format_datetime_for_dynamodb(report.created_at),
      "sync" => %{
        "missing_in_capway" => report.missing_in_capway,
        "missing_in_trinity" => report.missing_in_trinity,
        "existing_in_both" => report.existing_in_both,
        "missing_capway_count" => report.missing_capway_count,
        "missing_trinity_count" => report.missing_trinity_count,
        "existing_in_both_count" => report.existing_in_both_count
      },
      "actions" => %{
        # Action results
        "suspend" => %{
          "suspend_accounts" => report.suspend_accounts,
          "suspend_count" => report.suspend_count,
          "suspend_threshold" => report.suspend_threshold
        },
        "unsuspend" => %{
          "unsuspend_accounts" => report.unsuspend_accounts,
          "unsuspend_count" => report.unsuspend_count
        },
        "capway_cancellations" => %{
          "cancel_capway_contracts" => Map.get(report, :cancel_capway_contracts_ids, [])
        },
        "capway_new_contracts" => %{
          "create_capway_contracts" => Map.get(report, :missing_in_capway_ids, [])
        },
        "capway_updates" => %{
          "update_capway_contracts" => Map.get(report, :update_capway_contract_ids, []),
          "update_capway_contract_count" => Map.get(report, :update_capway_contract_count, 0)
        }
      },

      # Analysis metadata (stored as separate fields for DynamoDB expandability)
      "stats" => %{
        # Data comparison results
        "total_trinity" => report.total_trinity,
        "total_capway" => report.total_capway,
        "existing_in_both_count" => report.existing_in_both_count,
        # Execution metadata
        "execution_duration_ms" => report.execution_duration_ms,
        "execution_duration_formatted" => report.execution_duration_formatted,
        "suspend_total_analyzed" => report.analysis_metadata.suspend_total_analyzed,
        "unsuspend_total_analyzed" => report.analysis_metadata.unsuspend_total_analyzed,
        "suspend_collection_summary" => report.analysis_metadata.suspend_collection_summary,
        "unsuspend_collection_summary" => report.analysis_metadata.unsuspend_collection_summary,
        "unsuspend_unpaid_invoices_summary" =>
          report.analysis_metadata.unsuspend_unpaid_invoices_summary,
        "capway_customers_with_unpaid_invoices" =>
          report.analysis_metadata.capway.customers_with_unpaid_invoices,
        "capway_customers_with_collections" =>
          report.analysis_metadata.capway.customers_with_collections
      }
    }
  end

  defp dynamodb_item_to_struct(item) when is_map(item) do
    # Helper to safely get and decode JSON fields
    decode_json_field = fn key ->
      case Map.get(item, key, "[]") do
        json_string when is_binary(json_string) ->
          case Jason.decode(json_string) do
            {:ok, decoded} -> decoded
            {:error, _} -> []
          end

        _ ->
          []
      end
    end

    # Helper to get list fields (handling both JSON string and raw list)
    get_list_field = fn key ->
      val = Map.get(item, key, [])
      if is_list(val), do: val, else: []
    end

    # Reconstruct analysis metadata from separate DynamoDB fields
    analysis_metadata = %{
      suspend_total_analyzed: Map.get(item, "suspend_total_analyzed", 0),
      unsuspend_total_analyzed: Map.get(item, "unsuspend_total_analyzed", 0),
      suspend_collection_summary: Map.get(item, "suspend_collection_summary", %{}),
      unsuspend_collection_summary: Map.get(item, "unsuspend_collection_summary", %{}),
      unsuspend_unpaid_invoices_summary: Map.get(item, "unsuspend_unpaid_invoices_summary", %{}),
      capway: %{
        customers_with_unpaid_invoices: Map.get(item, "capway_customers_with_unpaid_invoices", 0),
        customers_with_collections: Map.get(item, "capway_customers_with_collections", 0)
      }
    }

    %GeneralSyncReport{
      # created_at is stored as ISO8601 string
      created_at: parse_datetime_from_dynamodb(Map.get(item, "created_at")),
      execution_duration_ms: Map.get(item, "execution_duration_ms", 0),
      execution_duration_formatted: Map.get(item, "execution_duration_formatted", "0ms"),

      # Data comparison results
      total_trinity: Map.get(item, "total_trinity", 0),
      total_capway: Map.get(item, "total_capway", 0),
      missing_capway_count: Map.get(item, "missing_capway_count", 0),
      missing_trinity_count: Map.get(item, "missing_trinity_count", 0),
      existing_in_both_count: Map.get(item, "existing_in_both_count", 0),
      update_capway_contract_count: Map.get(item, "update_capway_contract_count", 0),

      # Action results
      suspend_count: Map.get(item, "suspend_count", 0),
      suspend_threshold: Map.get(item, "suspend_threshold", 2),
      unsuspend_count: Map.get(item, "unsuspend_count", 0),
      cancel_capway_count: Map.get(item, "cancel_capway_count", 0),

      # Analysis metadata (nested structure)
      analysis_metadata: analysis_metadata,

      # Decode JSON fields
      missing_in_capway: decode_json_field.("missing_in_capway"),
      missing_in_trinity: decode_json_field.("missing_in_trinity"),
      existing_in_both: decode_json_field.("existing_in_both"),
      suspend_accounts: decode_json_field.("suspend_accounts"),
      unsuspend_accounts: decode_json_field.("unsuspend_accounts"),
      
      # For IDs which are stored as raw lists (or should be)
      missing_in_capway_ids: get_list_field.("create_capway_contracts"), # Mapped from create_capway_contracts
      missing_in_trinity_ids: [], # Not currently stored in actions
      existing_in_both_ids: [], # Not currently stored in actions
      
      cancel_capway_contracts: [], # We only store IDs now
      cancel_capway_contracts_ids: get_list_field.("cancel_capway_contracts"),
      
      update_capway_contract: [], # We only store IDs now
      update_capway_contract_ids: get_list_field.("update_capway_contracts")
    }
  end

  defp format_datetime_for_dynamodb(%DateTime{} = datetime) do
    DateTime.to_iso8601(datetime)
  end

  defp format_date_for_dynamodb(%DateTime{} = datetime) do
    datetime
    |> DateTime.to_date()
    |> Date.to_iso8601()
  end

  defp format_datetime_for_dynamodb(datetime) when is_binary(datetime) do
    # Assume it's already in ISO8601 format
    datetime
  end

  defp parse_datetime_from_dynamodb(nil), do: nil

  defp parse_datetime_from_dynamodb(iso_string) when is_binary(iso_string) do
    case DateTime.from_iso8601(iso_string) do
      {:ok, datetime, _offset} -> datetime
      {:error, _} -> nil
    end
  end

  defp maybe_add_date_filters(scan_params, opts) do
    start_date = Keyword.get(opts, :start_date)
    end_date = Keyword.get(opts, :end_date)

    cond do
      start_date && end_date ->
        Map.merge(scan_params, %{
          "FilterExpression" => "created_at BETWEEN :start_date AND :end_date",
          "ExpressionAttributeValues" => %{
            ":start_date" => format_datetime_for_dynamodb(start_date),
            ":end_date" => format_datetime_for_dynamodb(end_date)
          }
        })

      start_date ->
        Map.merge(scan_params, %{
          "FilterExpression" => "created_at >= :start_date",
          "ExpressionAttributeValues" => %{
            ":start_date" => format_datetime_for_dynamodb(start_date)
          }
        })

      end_date ->
        Map.merge(scan_params, %{
          "FilterExpression" => "created_at <= :end_date",
          "ExpressionAttributeValues" => %{
            ":end_date" => format_datetime_for_dynamodb(end_date)
          }
        })

      true ->
        scan_params
    end
  end
end
