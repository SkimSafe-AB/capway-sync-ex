defmodule CapwaySync.Dynamodb.ActionItemRepository do
  @moduledoc """
  Repository module for storing and retrieving ActionItem records in DynamoDB.

  This module handles the serialization, storage, and retrieval of ActionItem
  structs to/from a DynamoDB table. Each action item represents a specific task
  that needs to be processed, such as suspending an account or syncing to Capway.

  ## Configuration

  The DynamoDB table name can be configured via environment variables or application config:
  - `ACTION_ITEMS_TABLE` environment variable
  - Application config: `config :capway_sync, action_items_table: "action-items"`

  ## Table Schema

  The DynamoDB table should have the following structure:
  - **Partition Key**: `id` (String) - UUID of the action item
  - **Sort Key**: `created_at` (String) - Human-readable date format (YYYY-MM-DD) for chronological ordering
  - **Attributes**: All ActionItem fields stored as DynamoDB-compatible types

  ## Usage

      # Store an action item
      {:ok, item_id} = ActionItemRepository.store_action_item(action_item)

      # Retrieve a specific action item
      {:ok, item} = ActionItemRepository.get_action_item(item_id, created_at)

      # Query recent action items by type
      {:ok, items} = ActionItemRepository.list_action_items(action: "suspend", limit: 10)

      # Store multiple action items from a sync report
      {:ok, results} = ActionItemRepository.store_action_items_from_report(report)
  """

  alias CapwaySync.Models.ActionItem
  alias CapwaySync.Dynamodb.Client

  require Logger

  @table_name_env "ACTION_ITEMS_TABLE"
  @default_table_name "capway-sync-action-items"

  @doc """
  Stores an ActionItem to DynamoDB.

  Automatically generates a UUID for the item if not already set and serializes
  the item to DynamoDB-compatible format.

  ## Parameters
  - `action_item`: %ActionItem{} struct to store

  ## Returns
  - `{:ok, item_id}` on success - returns the UUID for the action item
  - `{:error, reason}` on failure

  ## Examples

      iex> item = %ActionItem{trinity_id: "123", action: "suspend", ...}
      iex> {:ok, item_id} = ActionItemRepository.store_action_item(item)
      iex> is_binary(item_id)
      true
  """
  def store_action_item(%ActionItem{} = action_item) do
    item_id = action_item.id || UUID.uuid4()
    table_name = get_table_name()

    # Ensure id is set
    action_item = %{action_item | id: item_id}

    # Convert to DynamoDB item format
    dynamodb_item = struct_to_dynamodb_item(action_item)

    Logger.info(
      "Storing ActionItem to DynamoDB table: #{table_name}, item_id: #{item_id}, action: #{action_item.action}"
    )

    case Client.put_item(table_name, dynamodb_item) do
      {:ok, _result} ->
        Logger.info("Successfully stored ActionItem with ID: #{item_id}")
        {:ok, item_id}

      {:error, reason} = error ->
        Logger.error("Failed to store ActionItem: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Stores multiple ActionItems from a GeneralSyncReport.

  Creates ActionItem records for all actionable items in the report and stores
  them as a batch operation to DynamoDB.

  ## Parameters
  - `report`: %GeneralSyncReport{} struct containing actionable data

  ## Returns
  - `{:ok, %{stored: count, failed: count, item_ids: [item_id]}}` on success
  - `{:error, reason}` on failure

  ## Examples

      iex> report = %GeneralSyncReport{suspend_accounts: ["123"], ...}
      iex> {:ok, result} = ActionItemRepository.store_action_items_from_report(report)
      iex> result.stored
      1
  """
  def store_action_items_from_report(%CapwaySync.Models.GeneralSyncReport{} = report) do
    action_items = ActionItem.create_action_items_from_report(report)

    Logger.info("Storing #{length(action_items)} action items from sync report")

    results = Enum.map(action_items, &store_action_item/1)

    # Aggregate results
    {successes, failures} =
      Enum.split_with(results, fn
        {:ok, _} -> true
        {:error, _} -> false
      end)

    item_ids = Enum.map(successes, fn {:ok, item_id} -> item_id end)

    result = %{
      stored: length(successes),
      failed: length(failures),
      item_ids: item_ids
    }

    Logger.info("ActionItems storage completed: #{result.stored} stored, #{result.failed} failed")

    if result.failed > 0 do
      failure_reasons = Enum.map(failures, fn {:error, reason} -> reason end)
      Logger.error("ActionItems storage failures: #{inspect(failure_reasons)}")
    end

    {:ok, result}
  end

  @doc """
  Retrieves an ActionItem from DynamoDB by id and created_at.

  ## Parameters
  - `item_id`: UUID string of the action item
  - `created_at`: Human-readable date string (YYYY-MM-DD) of when the item was created

  ## Returns
  - `{:ok, %ActionItem{}}` on success
  - `{:ok, nil}` if item not found
  - `{:error, reason}` on failure
  """
  def get_action_item(item_id, created_at) when is_binary(item_id) and is_binary(created_at) do
    table_name = get_table_name()

    key = %{
      "id" => item_id,
      "created_at" => created_at
    }

    Logger.debug("Retrieving ActionItem from #{table_name} with key: #{inspect(key)}")

    case Client.get_item(table_name, key) do
      {:ok, %{"Item" => item}} when map_size(item) > 0 ->
        action_item = dynamodb_item_to_struct(item)
        {:ok, action_item}

      {:ok, _empty_result} ->
        Logger.debug("ActionItem not found for id: #{item_id}")
        {:ok, nil}

      {:error, reason} = error ->
        Logger.error("Failed to retrieve ActionItem: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Lists ActionItem records from DynamoDB with optional filtering.

  Uses a scan operation to retrieve action items. For better performance in production,
  consider implementing GSI for action type and date range queries.

  ## Parameters
  - `opts`: Keyword list of options
    - `:limit` - Maximum number of items to return (default: 50)
    - `:action` - Filter by action type ("suspend", "unsuspend", "sync_to_capway")
    - `:start_date` - Only return items after this date string (YYYY-MM-DD)
    - `:end_date` - Only return items before this date string (YYYY-MM-DD)
    - `:trinity_id` - Filter by specific trinity_id

  ## Returns
  - `{:ok, [%ActionItem{}]}` on success
  - `{:error, reason}` on failure

  ## Examples

      iex> {:ok, items} = ActionItemRepository.list_action_items(action: "suspend", limit: 10)
      iex> Enum.all?(items, fn item -> item.action == "suspend" end)
      true
  """
  def list_action_items(opts \\ []) do
    table_name = get_table_name()
    limit = Keyword.get(opts, :limit, 50)

    scan_params = %{
      "TableName" => table_name,
      "Limit" => limit
    }

    scan_params = maybe_add_filters(scan_params, opts)

    Logger.debug("Scanning ActionItem table: #{table_name} with params: #{inspect(scan_params)}")

    case ExAws.Dynamo.scan(scan_params) |> ExAws.request() do
      {:ok, %{"Items" => items}} ->
        action_items = Enum.map(items, &dynamodb_item_to_struct/1)
        # Sort by timestamp descending (since created_at is now a string)
        action_items = Enum.sort_by(action_items, & &1.timestamp, :desc)
        {:ok, action_items}

      {:error, reason} = error ->
        Logger.error("Failed to scan ActionItem table: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Deletes an ActionItem from DynamoDB.

  ## Parameters
  - `item_id`: UUID string of the action item to delete
  - `created_at`: Human-readable date string (YYYY-MM-DD) of when the item was created

  ## Returns
  - `{:ok, :deleted}` on success
  - `{:error, reason}` on failure
  """
  def delete_action_item(item_id, created_at) when is_binary(item_id) and is_binary(created_at) do
    table_name = get_table_name()

    key = %{
      "id" => item_id,
      "created_at" => created_at
    }

    Logger.info("Deleting ActionItem from #{table_name} with key: #{inspect(key)}")

    case Client.delete_item(table_name, key) do
      {:ok, _result} ->
        Logger.info("Successfully deleted ActionItem with ID: #{item_id}")
        {:ok, :deleted}

      {:error, reason} = error ->
        Logger.error("Failed to delete ActionItem: #{inspect(reason)}")
        error
    end
  end

  # Private helper functions

  defp get_table_name do
    System.get_env(@table_name_env) ||
      Application.get_env(:capway_sync, :action_items_table) ||
      @default_table_name
  end

  defp struct_to_dynamodb_item(%ActionItem{} = action_item) do
    %{
      "id" => action_item.id,
      "trinity_id" => action_item.trinity_id,
      "created_at" => action_item.created_at,
      "timestamp" => action_item.timestamp,
      "action" => action_item.action,
      "status" => Atom.to_string(action_item.status)
    }
  end

  defp dynamodb_item_to_struct(item) when is_map(item) do
    %ActionItem{
      id: Map.get(item, "id"),
      trinity_id: Map.get(item, "trinity_id"),
      created_at: Map.get(item, "created_at"),
      timestamp: Map.get(item, "timestamp", 0),
      action: Map.get(item, "action"),
      status: Map.get(item, "status") |> to_atom_safe()
    }
  end

  defp to_atom_safe(nil), do: :pending

  defp to_atom_safe(str) when is_binary(str) do
    case String.to_existing_atom(str) do
      atom when atom in [:pending, :in_progress, :completed, :failed] -> atom
      _ -> :pending
    end
  rescue
    ArgumentError -> :pending
  end

  defp maybe_add_filters(scan_params, opts) do
    filters = []
    expression_values = %{}

    # Add action filter
    {filters, expression_values} =
      case Keyword.get(opts, :action) do
        nil ->
          {filters, expression_values}

        action ->
          filter = "action = :action"
          values = Map.put(expression_values, ":action", action)
          {[filter | filters], values}
      end

    # Add trinity_id filter
    {filters, expression_values} =
      case Keyword.get(opts, :trinity_id) do
        nil ->
          {filters, expression_values}

        trinity_id ->
          filter = "trinity_id = :trinity_id"
          values = Map.put(expression_values, ":trinity_id", trinity_id)
          {[filter | filters], values}
      end

    # Add date range filters (using created_at string field for comparison)
    {filters, expression_values} =
      case {Keyword.get(opts, :start_date), Keyword.get(opts, :end_date)} do
        {nil, nil} ->
          {filters, expression_values}

        {start_date, nil} when is_binary(start_date) ->
          filter = "created_at >= :start_date"
          values = Map.put(expression_values, ":start_date", start_date)
          {[filter | filters], values}

        {nil, end_date} when is_binary(end_date) ->
          filter = "created_at <= :end_date"
          values = Map.put(expression_values, ":end_date", end_date)
          {[filter | filters], values}

        {start_date, end_date} when is_binary(start_date) and is_binary(end_date) ->
          filter = "created_at BETWEEN :start_date AND :end_date"

          values =
            expression_values
            |> Map.put(":start_date", start_date)
            |> Map.put(":end_date", end_date)

          {[filter | filters], values}

        _ ->
          {filters, expression_values}
      end

    # Apply filters if any exist
    if length(filters) > 0 do
      filter_expression = Enum.join(filters, " AND ")

      scan_params
      |> Map.put("FilterExpression", filter_expression)
      |> Map.put("ExpressionAttributeValues", expression_values)
    else
      scan_params
    end
  end
end
