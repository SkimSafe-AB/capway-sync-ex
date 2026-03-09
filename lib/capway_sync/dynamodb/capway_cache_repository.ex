defmodule CapwaySync.Dynamodb.CapwayCacheRepository do
  @moduledoc """
  Repository for caching Capway subscriber data in DynamoDB.

  Capway's SOAP API is slow and only updates once per day, so this cache
  stores fetched subscriber data keyed by date. Subscribers are chunked
  into groups of 200 to stay within DynamoDB's 400KB item size limit.

  A manifest item per date tracks metadata (total count, chunk count, timestamp).
  Items have a TTL of 2 days for automatic cleanup.
  """

  alias CapwaySync.Dynamodb.Client
  alias CapwaySync.Models.CapwaySubscriber

  require Logger

  @table_name_env "CAPWAY_CACHE_TABLE"
  @default_table_name "capway-subscriber-cache"
  @chunk_size 200
  @ttl_days 2

  @doc """
  Returns the configured chunk size for splitting subscriber lists.
  """
  @spec chunk_size() :: pos_integer()
  def chunk_size, do: @chunk_size

  @doc """
  Reads cached subscriber data for the given date string.

  Returns `{:ok, subscribers}` if a valid cache exists, or `{:miss}` if not found.
  """
  @spec read_cache(String.t()) :: {:ok, [%CapwaySubscriber{}]} | {:miss} | {:error, term()}
  def read_cache(date_string) do
    table_name = table_name()

    case Client.get_item(table_name, %{"cache_date" => date_string, "chunk_id" => "manifest"}) do
      {:ok, %{"Item" => manifest}} ->
        chunk_count = manifest["chunk_count"]["N"] |> String.to_integer()
        fetch_all_chunks(table_name, date_string, chunk_count)

      {:ok, %{}} ->
        {:miss}

      {:error, reason} ->
        Logger.error("Failed to read cache manifest: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Writes subscriber data to cache for the given date string.

  Chunks the subscriber list and writes a manifest plus chunk items.
  """
  @spec write_cache(String.t(), [%CapwaySubscriber{}]) :: :ok | {:error, term()}
  def write_cache(date_string, subscribers) do
    table_name = table_name()
    chunks = Enum.chunk_every(subscribers, @chunk_size)
    chunk_count = length(chunks)
    ttl = calculate_ttl()

    manifest = %{
      "cache_date" => date_string,
      "chunk_id" => "manifest",
      "total_subscribers" => length(subscribers),
      "chunk_count" => chunk_count,
      "created_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "ttl" => ttl
    }

    with {:ok, _} <- Client.put_item(table_name, manifest) do
      write_chunks(table_name, date_string, chunks, ttl)
    else
      {:error, reason} ->
        Logger.error("Failed to write cache manifest: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Returns `true` if cache bypass is enabled via `CAPWAY_CACHE_BYPASS` env var.
  """
  @spec bypass?() :: boolean()
  def bypass? do
    System.get_env("CAPWAY_CACHE_BYPASS") == "true"
  end

  @doc """
  Serializes a `%CapwaySubscriber{}` to a plain map for JSON encoding.

  Excludes the `raw_data` field to save space.
  """
  @spec serialize_subscriber(%CapwaySubscriber{}) :: map()
  def serialize_subscriber(%CapwaySubscriber{} = subscriber) do
    subscriber
    |> Map.from_struct()
    |> Map.delete(:raw_data)
    |> Map.new(fn {k, v} -> {Atom.to_string(k), v} end)
  end

  @doc """
  Deserializes a plain map (with string keys) back to a `%CapwaySubscriber{}`.
  """
  @spec deserialize_subscriber(map()) :: %CapwaySubscriber{}
  def deserialize_subscriber(map) when is_map(map) do
    fields =
      map
      |> Map.new(fn {k, v} -> {String.to_existing_atom(k), v} end)
      |> Map.put(:raw_data, nil)

    struct(CapwaySubscriber, fields)
  end

  @doc """
  Builds a manifest map from a date string and subscriber list.

  Useful for testing manifest structure.
  """
  @spec build_manifest(String.t(), [%CapwaySubscriber{}]) :: map()
  def build_manifest(date_string, subscribers) do
    chunks = Enum.chunk_every(subscribers, @chunk_size)

    %{
      "cache_date" => date_string,
      "chunk_id" => "manifest",
      "total_subscribers" => length(subscribers),
      "chunk_count" => length(chunks),
      "created_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "ttl" => calculate_ttl()
    }
  end

  # Private helpers

  defp table_name do
    System.get_env(@table_name_env, @default_table_name)
  end

  defp calculate_ttl do
    DateTime.utc_now()
    |> DateTime.add(@ttl_days * 24 * 60 * 60, :second)
    |> DateTime.to_unix()
  end

  defp fetch_all_chunks(table_name, date_string, chunk_count) do
    results =
      0..(chunk_count - 1)
      |> Enum.reduce_while([], fn index, acc ->
        chunk_id = "chunk_#{index}"
        key = %{"cache_date" => date_string, "chunk_id" => chunk_id}

        case Client.get_item(table_name, key) do
          {:ok, %{"Item" => item}} ->
            subscribers_json = item["subscribers"]["S"]

            case Jason.decode(subscribers_json) do
              {:ok, subscriber_maps} ->
                subscribers = Enum.map(subscriber_maps, &deserialize_subscriber/1)
                {:cont, acc ++ subscribers}

              {:error, reason} ->
                {:halt, {:error, {:json_decode_error, chunk_id, reason}}}
            end

          {:ok, %{}} ->
            Logger.warning("Cache chunk #{chunk_id} missing for date #{date_string}")
            {:halt, {:error, {:missing_chunk, chunk_id}}}

          {:error, reason} ->
            {:halt, {:error, reason}}
        end
      end)

    case results do
      {:error, _} = error -> error
      subscribers when is_list(subscribers) -> {:ok, subscribers}
    end
  end

  defp write_chunks(table_name, date_string, chunks, ttl) do
    chunks
    |> Enum.with_index()
    |> Enum.reduce_while(:ok, fn {chunk, index}, :ok ->
      serialized = Enum.map(chunk, &serialize_subscriber/1)
      subscribers_json = Jason.encode!(serialized)

      item = %{
        "cache_date" => date_string,
        "chunk_id" => "chunk_#{index}",
        "subscribers" => subscribers_json,
        "ttl" => ttl
      }

      case Client.put_item(table_name, item) do
        {:ok, _} ->
          {:cont, :ok}

        {:error, reason} ->
          Logger.error("Failed to write cache chunk_#{index}: #{inspect(reason)}")
          {:halt, {:error, reason}}
      end
    end)
  end
end
