defmodule CapwaySync.Reactor.V1.Steps.CompareData do
  @moduledoc """
  Compares Trinity subscribers with Capway subscribers and identifies missing items.

  Both datasets are CapwaySubscriber structs after Trinity data conversion, so they
  have the same field structure and can be compared using the same keys.

  The Trinity data is considered the master data and Capway data is the data to be synced.

  ## Returns

  A map containing:
  - `missing_in_capway`: Subscribers present in Trinity but missing in Capway (to be added to Capway)
  - `missing_in_trinity`: Subscribers present in Capway but missing in Trinity (to be removed from Capway)
  - `existing_in_both`: Subscribers present in both systems
  - `cancel_capway_contracts`: Trinity subscribers with payment method changed from "capway", enriched with `:capway_active_status` field
  - `total_trinity`: Total count of Trinity subscribers
  - `total_capway`: Total count of Capway subscribers
  - `missing_capway_count`: Count of items missing in Capway
  - `missing_trinity_count`: Count of items missing in Trinity
  - `existing_in_both_count`: Count of items existing in both systems

  ## Configuration

  Supports configurable key mapping through options:
  - `trinity_key`: Key to use for Trinity data comparison (default: `:id_number`)
  - `capway_key`: Key to use for Capway data comparison (default: `:id_number`)

  Since both datasets are CapwaySubscriber structs, they typically use the same key.
  """

  use Reactor.Step

  require Logger

  @impl Reactor.Step
  def run(arguments, _context, options \\ []) do
    Logger.info("Starting data comparison between Trinity and Capway subscribers")

    # Default to comparing id_number for both since both are CapwaySubscriber structs after conversion
    trinity_key = Keyword.get(options, :trinity_key, :id_number)
    capway_key = Keyword.get(options, :capway_key, :id_number)

    with {:ok, trinity_subscribers} <- validate_argument(arguments, :trinity_subscribers),
         {:ok, capway_subscribers} <- validate_argument(arguments, :capway_subscribers) do
      result =
        find_missing_items(
          trinity_subscribers,
          capway_subscribers,
          trinity_key,
          capway_key
        )

      Logger.info(
        "Data comparison completed: #{result.missing_capway_count} missing in Capway, #{result.missing_trinity_count} missing in Trinity"
      )

      {:ok, result}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Finds items missing in each dataset and items existing in both datasets by comparing key values.

  Uses MapSet for O(1) lookups for optimal performance with large datasets.

  Now also identifies subscribers that need Capway contract cancellation:
  - Trinity subscribers with payment_method != "capway" that exist in Capway
  """
  def find_missing_items(trinity_list, capway_list, trinity_key, capway_key)
      when is_list(trinity_list) and is_list(capway_list) do
    # Partition Trinity subscribers into those with/without valid keys
    {valid_trinity_list, invalid_trinity_list} =
      Enum.split_with(trinity_list, fn item ->
        case Map.get(item, trinity_key) do
          nil -> false
          "" -> false
          _ -> true
        end
      end)

    Logger.info(
      "Found #{length(invalid_trinity_list)} Trinity subscribers without valid #{trinity_key}"
    )

    # Extract key values for efficient comparison (using only valid items)
    trinity_keys = extract_key_values(valid_trinity_list, trinity_key) |> MapSet.new()
    capway_keys = extract_key_values(capway_list, capway_key) |> MapSet.new()

    # Debug logging to understand what's being compared
    Logger.debug("🔍 Comparison Debug Info:")
    Logger.debug("   Trinity key: #{trinity_key}, Capway key: #{capway_key}")

    Logger.debug(
      "   Valid Trinity count: #{length(valid_trinity_list)}, Capway count: #{length(capway_list)}"
    )

    Logger.debug("   Trinity keys sample: #{trinity_keys |> Enum.take(5) |> inspect()}")
    Logger.debug("   Capway keys sample: #{capway_keys |> Enum.take(5) |> inspect()}")
    Logger.debug("   Trinity keys size: #{MapSet.size(trinity_keys)}")
    Logger.debug("   Capway keys size: #{MapSet.size(capway_keys)}")

    # Find missing key values
    _missing_capway_keys = MapSet.difference(trinity_keys, capway_keys)
    missing_trinity_keys = MapSet.difference(capway_keys, trinity_keys)

    # Find existing key values (intersection of both sets)
    existing_keys = MapSet.intersection(trinity_keys, capway_keys)

    Logger.debug("   Intersection size: #{MapSet.size(existing_keys)}")
    Logger.debug("   Sample intersection keys: #{existing_keys |> Enum.take(5) |> inspect()}")

    # Create a map of Capway subscribers for efficient status lookup
    capway_map = Map.new(capway_list, fn sub -> {Map.get(sub, capway_key), sub} end)

    # Find Trinity subscribers with payment_method != "capway" that exist in Capway
    # and have an "active" status in Capway.
    # These need contract cancellation in Capway.
    cancel_capway_keys =
      valid_trinity_list
      |> Enum.filter(fn subscriber ->
        key_value = Map.get(subscriber, trinity_key)
        payment_method = Map.get(subscriber, :payment_method)

        if key_value && payment_method != "capway" && MapSet.member?(capway_keys, key_value) do
          capway_subscriber = Map.get(capway_map, key_value)
          capway_subscriber && capway_subscriber.active == true
        else
          false
        end
      end)
      |> extract_key_values(trinity_key)
      |> MapSet.new()

    Logger.debug("   Cancel Capway contracts size: #{MapSet.size(cancel_capway_keys)}")

    # Filter Trinity subscribers to only include those with payment_method == "capway"
    # AND status != :cancelled (exclude cancelled subscriptions)
    # for the missing_in_capway comparison (these should be added to Capway)
    capway_payment_trinity_keys =
      valid_trinity_list
      |> Enum.filter(fn subscriber ->
        Map.get(subscriber, :payment_method) == "capway" &&
          Map.get(subscriber, :status) != :cancelled
      end)
      |> extract_key_values(trinity_key)
      |> MapSet.new()

    # Recalculate missing_capway_keys to only include Trinity subscribers with payment_method == "capway"
    filtered_missing_capway_keys = MapSet.difference(capway_payment_trinity_keys, capway_keys)

    # Find the actual items for analysis
    # Include invalid_trinity_list in missing_in_capway candidates first
    initial_missing_in_capway =
      find_items_by_keys(valid_trinity_list, filtered_missing_capway_keys, trinity_key) ++
        invalid_trinity_list

    # Separate "update_capway_contract" candidates from "missing_in_capway"
    # Logic: If Trinity ID exists in Capway (via customer_ref/capway_id) AND Capway has missing/nil id_number
    # then it's an UPDATE, not a CREATE.

    # Map Capway subscribers by capway_id (customer_ref) for lookup
    capway_by_ref = Map.new(capway_list, fn sub -> {Map.get(sub, :capway_id), sub} end)

    {update_capway_contract, missing_in_capway} =
      Enum.split_with(initial_missing_in_capway, fn trinity_sub ->
        trinity_id = Map.get(trinity_sub, :trinity_id)

        if trinity_id do
          case Map.get(capway_by_ref, to_string(trinity_id)) do
            # Not in Capway -> Missing (Create)
            nil ->
              false

            capway_sub ->
              # In Capway. Check if Capway id_number is missing.
              case Map.get(capway_sub, :id_number) do
                # Capway missing id_number -> Update
                nil -> true
                # Capway empty id_number -> Update
                "" -> true
                # Capway has id_number -> Mismatch/Conflict (Keep as Missing/Create logic)
                _ -> false
              end
          end
        else
          false
        end
      end)

    missing_in_trinity = find_items_by_keys(capway_list, missing_trinity_keys, capway_key)
    existing_in_both = find_items_by_keys(capway_list, existing_keys, capway_key)

    # Enrich Trinity subscribers with Capway active status for cancellation tracking
    cancel_capway_contracts =
      find_items_by_keys(valid_trinity_list, cancel_capway_keys, trinity_key)
      |> Enum.map(fn subscriber ->
        key_value = Map.get(subscriber, trinity_key)
        capway_subscriber = Map.get(capway_map, key_value)
        capway_active = if capway_subscriber, do: capway_subscriber.active, else: nil

        Map.put(subscriber, :capway_active_status, capway_active)
      end)

    # Extract ID lists for minimal report storage
    # Helper to extract IDs from a list of structs (handling both valid/invalid key items)
    extract_ids_helper = fn items ->
      Enum.map(items, fn item ->
        Map.get(item, :trinity_id) || Map.get(item, :capway_id) || Map.get(item, trinity_key)
      end)
      |> Enum.reject(&is_nil/1)
    end

    missing_in_capway_ids = extract_ids_helper.(missing_in_capway)
    update_capway_contract_ids = extract_ids_helper.(update_capway_contract)

    missing_in_trinity_ids = extract_trinity_ids(capway_list, missing_trinity_keys, capway_key)
    existing_in_both_ids = extract_trinity_ids(capway_list, existing_keys, capway_key)

    cancel_capway_contracts_ids =
      extract_trinity_ids(valid_trinity_list, cancel_capway_keys, trinity_key)

    %{
      # Full objects for suspend/unsuspend/cancel analysis
      missing_in_capway: missing_in_capway,
      missing_in_trinity: missing_in_trinity,
      existing_in_both: existing_in_both,
      cancel_capway_contracts: cancel_capway_contracts,
      update_capway_contract: update_capway_contract,
      # ID lists for report storage
      missing_in_capway_ids: missing_in_capway_ids,
      missing_in_trinity_ids: missing_in_trinity_ids,
      existing_in_both_ids: existing_in_both_ids,
      cancel_capway_contracts_ids: cancel_capway_contracts_ids,
      update_capway_contract_ids: update_capway_contract_ids,
      # Counts and totals
      total_trinity: length(trinity_list),
      total_capway: length(capway_list),
      missing_capway_count: length(missing_in_capway),
      missing_trinity_count: length(missing_in_trinity),
      existing_in_both_count: length(existing_in_both),
      cancel_capway_contracts_count: length(cancel_capway_contracts),
      update_capway_contract_count: length(update_capway_contract)
    }
  end

  @doc """
  Extracts key values from a list of maps, handling nil values gracefully.
  """
  def extract_key_values(items, key) when is_list(items) do
    items
    |> Enum.map(&Map.get(&1, key))
    # Remove nil values for cleaner comparison
    |> Enum.reject(&is_nil/1)
  end

  @doc """
  Finds items from a list where the specified key matches any value in the keys set.
  """
  def find_items_by_keys(items, keys_set, key) when is_list(items) do
    items
    |> Enum.filter(fn item ->
      item_key = Map.get(item, key)
      item_key && MapSet.member?(keys_set, item_key)
    end)
  end

  @doc """
  Extracts subscriber IDs from items that match the keys set.
  Returns a list of IDs for minimal storage in reports.
  Prefers trinity_id, falls back to capway_id, then to comparison key value.
  """
  def extract_trinity_ids(items, keys_set, key) when is_list(items) do
    items
    |> Enum.filter(fn item ->
      item_key = Map.get(item, key)
      item_key && MapSet.member?(keys_set, item_key)
    end)
    |> Enum.map(fn item ->
      # Prefer trinity_id, fall back to capway_id, then to key value for identification
      Map.get(item, :trinity_id) || Map.get(item, :capway_id) || Map.get(item, key)
    end)
    |> Enum.reject(&is_nil/1)
  end

  @doc """
  Legacy function for backward compatibility with existing tests.
  Compares two lists by their key values and returns true if they match exactly.
  """
  def compare_with_keys(%{
        capway_list: capway_list,
        trinity_list: trinity_list,
        capway_key: capway_key,
        trinity_key: trinity_key
      })
      when is_list(capway_list) and is_list(trinity_list) do
    capway_values = Enum.map(capway_list, &Map.get(&1, capway_key))
    trinity_values = Enum.map(trinity_list, &Map.get(&1, trinity_key))

    capway_values == trinity_values
  end

  # Private helper functions

  defp validate_argument(arguments, key) do
    case Map.get(arguments, key) do
      nil -> {:error, "Missing required argument: #{key}"}
      # Empty list is valid
      [] -> {:ok, []}
      value when is_list(value) -> {:ok, value}
      _ -> {:error, "Argument #{key} must be a list"}
    end
  end
end
