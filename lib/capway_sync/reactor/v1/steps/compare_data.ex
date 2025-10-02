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
    # Extract key values for efficient comparison
    IO.inspect("Trinity list length: #{length(trinity_list)}")
    IO.inspect("Trinity sample: #{Enum.take(trinity_list, 3) |> inspect()}")
    trinity_keys = extract_key_values(trinity_list, trinity_key) |> MapSet.new()
    capway_keys = extract_key_values(capway_list, capway_key) |> MapSet.new()

    # Debug logging to understand what's being compared
    Logger.debug("🔍 Comparison Debug Info:")
    Logger.debug("   Trinity key: #{trinity_key}, Capway key: #{capway_key}")

    Logger.debug(
      "   Trinity count: #{length(trinity_list)}, Capway count: #{length(capway_list)}"
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

    # Find Trinity subscribers with payment_method != "capway" that exist in Capway
    # These need contract cancellation in Capway
    cancel_capway_keys =
      trinity_list
      |> Enum.filter(fn subscriber ->
        key_value = Map.get(subscriber, trinity_key)
        payment_method = Map.get(subscriber, :payment_method)
        key_value && payment_method != "capway" && MapSet.member?(capway_keys, key_value)
      end)
      |> extract_key_values(trinity_key)
      |> MapSet.new()

    Logger.debug("   Cancel Capway contracts size: #{MapSet.size(cancel_capway_keys)}")

    # Filter Trinity subscribers to only include those with payment_method == "capway"
    # for the missing_in_capway comparison (these should be added to Capway)
    capway_payment_trinity_keys =
      trinity_list
      |> Enum.filter(fn subscriber ->
        Map.get(subscriber, :payment_method) == "capway"
      end)
      |> extract_key_values(trinity_key)
      |> MapSet.new()

    # Recalculate missing_capway_keys to only include Trinity subscribers with payment_method == "capway"
    filtered_missing_capway_keys = MapSet.difference(capway_payment_trinity_keys, capway_keys)

    # Find the actual items for analysis
    missing_in_capway = find_items_by_keys(trinity_list, filtered_missing_capway_keys, trinity_key)
    missing_in_trinity = find_items_by_keys(capway_list, missing_trinity_keys, capway_key)
    existing_in_both = find_items_by_keys(capway_list, existing_keys, capway_key)
    cancel_capway_contracts = find_items_by_keys(trinity_list, cancel_capway_keys, trinity_key)

    # Extract ID lists for minimal report storage
    missing_in_capway_ids = extract_trinity_ids(trinity_list, filtered_missing_capway_keys, trinity_key)
    missing_in_trinity_ids = extract_trinity_ids(capway_list, missing_trinity_keys, capway_key)
    existing_in_both_ids = extract_trinity_ids(capway_list, existing_keys, capway_key)
    cancel_capway_contracts_ids = extract_trinity_ids(trinity_list, cancel_capway_keys, trinity_key)

    %{
      # Full objects for suspend/unsuspend/cancel analysis
      missing_in_capway: missing_in_capway,
      missing_in_trinity: missing_in_trinity,
      existing_in_both: existing_in_both,
      cancel_capway_contracts: cancel_capway_contracts,
      # ID lists for report storage
      missing_in_capway_ids: missing_in_capway_ids,
      missing_in_trinity_ids: missing_in_trinity_ids,
      existing_in_both_ids: existing_in_both_ids,
      cancel_capway_contracts_ids: cancel_capway_contracts_ids,
      # Counts and totals
      total_trinity: length(trinity_list),
      total_capway: length(capway_list),
      missing_capway_count: length(missing_in_capway),
      missing_trinity_count: length(missing_in_trinity),
      existing_in_both_count: length(existing_in_both),
      cancel_capway_contracts_count: length(cancel_capway_contracts)
    }
  end

  @doc """
  Extracts key values from a list of maps, handling nil values gracefully.
  """
  def extract_key_values(items, key) when is_list(items) do
    IO.inspect("Extracting key values for key: #{key}")
    IO.inspect("Total items: #{length(items)}")

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
