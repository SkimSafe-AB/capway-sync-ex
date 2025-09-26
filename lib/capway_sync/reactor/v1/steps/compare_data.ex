defmodule CapwaySync.Reactor.V1.Steps.CompareData do
  @moduledoc """
  Compares Trinity subscribers with Capway subscribers and identifies missing items.

  The Trinity data is considered the master data and Capway data is the data to be synced.

  ## Returns

  A map containing:
  - `missing_in_capway`: Subscribers present in Trinity but missing in Capway (to be added to Capway)
  - `missing_in_trinity`: Subscribers present in Capway but missing in Trinity (to be removed from Capway)
  - `total_trinity`: Total count of Trinity subscribers
  - `total_capway`: Total count of Capway subscribers
  - `missing_capway_count`: Count of items missing in Capway
  - `missing_trinity_count`: Count of items missing in Trinity

  ## Configuration

  Supports configurable key mapping through options:
  - `trinity_key`: Key to use for Trinity data comparison (default: `:id`)
  - `capway_key`: Key to use for Capway data comparison (default: `:customer_ref`)
  """

  use Reactor.Step

  require Logger

  @impl Reactor.Step
  def run(arguments, _context, options \\ []) do
    Logger.info("Starting data comparison between Trinity and Capway subscribers")

    trinity_key = Keyword.get(options, :trinity_key, :id)
    capway_key = Keyword.get(options, :capway_key, :customer_ref)

    with {:ok, trinity_subscribers} <- validate_argument(arguments, :trinity_subscribers),
         {:ok, capway_subscribers} <- validate_argument(arguments, :capway_subscribers) do

      result = find_missing_items(
        trinity_subscribers,
        capway_subscribers,
        trinity_key,
        capway_key
      )

      Logger.info("Data comparison completed: #{result.missing_capway_count} missing in Capway, #{result.missing_trinity_count} missing in Trinity")

      {:ok, result}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Finds items missing in each dataset and items existing in both datasets by comparing key values.

  Uses MapSet for O(1) lookups for optimal performance with large datasets.
  """
  def find_missing_items(trinity_list, capway_list, trinity_key, capway_key)
      when is_list(trinity_list) and is_list(capway_list) do

    # Extract key values for efficient comparison
    trinity_keys = extract_key_values(trinity_list, trinity_key) |> MapSet.new()
    capway_keys = extract_key_values(capway_list, capway_key) |> MapSet.new()

    # Find missing key values
    missing_capway_keys = MapSet.difference(trinity_keys, capway_keys)
    missing_trinity_keys = MapSet.difference(capway_keys, trinity_keys)

    # Find existing key values (intersection of both sets)
    existing_keys = MapSet.intersection(trinity_keys, capway_keys)

    # Find the actual items corresponding to keys
    missing_in_capway = find_items_by_keys(trinity_list, missing_capway_keys, trinity_key)
    missing_in_trinity = find_items_by_keys(capway_list, missing_trinity_keys, capway_key)
    existing_in_both = find_items_by_keys(capway_list, existing_keys, capway_key)

    %{
      missing_in_capway: missing_in_capway,
      missing_in_trinity: missing_in_trinity,
      existing_in_both: existing_in_both,
      total_trinity: length(trinity_list),
      total_capway: length(capway_list),
      missing_capway_count: length(missing_in_capway),
      missing_trinity_count: length(missing_in_trinity),
      existing_in_both_count: length(existing_in_both)
    }
  end

  @doc """
  Extracts key values from a list of maps, handling nil values gracefully.
  """
  def extract_key_values(items, key) when is_list(items) do
    items
    |> Enum.map(&Map.get(&1, key))
    |> Enum.reject(&is_nil/1)  # Remove nil values for cleaner comparison
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
      [] -> {:ok, []}  # Empty list is valid
      value when is_list(value) -> {:ok, value}
      _ -> {:error, "Argument #{key} must be a list"}
    end
  end
end
