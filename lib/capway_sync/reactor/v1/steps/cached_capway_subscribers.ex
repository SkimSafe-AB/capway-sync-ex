defmodule CapwaySync.Reactor.V1.Steps.CachedCapwaySubscribers do
  @moduledoc """
  Reactor step that wraps `CapwaySubscribers` with a DynamoDB cache layer.

  Capway's SOAP API is slow and only updates once per day. This step checks
  the cache first and only falls through to the SOAP API on a cache miss
  or when bypass is enabled via `CAPWAY_CACHE_BYPASS=true`.
  """

  use Reactor.Step

  alias CapwaySync.Reactor.V1.Steps.CapwaySubscribers
  alias CapwaySync.Dynamodb.CapwayCacheRepository

  require Logger

  @impl true
  def run(arguments, context, options) do
    today = Date.utc_today() |> Date.to_string()

    if CapwayCacheRepository.bypass?() do
      Logger.info("Cache bypass enabled, fetching fresh data from Capway SOAP API")
      fetch_and_cache(arguments, context, options, today)
    else
      case CapwayCacheRepository.read_cache(today) do
        {:ok, subscribers} ->
          Logger.info(
            "Cache hit for #{today}: returning #{length(subscribers)} cached subscribers"
          )

          {:ok, subscribers}

        {:miss} ->
          Logger.info("Cache miss for #{today}, fetching from Capway SOAP API")
          fetch_and_cache(arguments, context, options, today)

        {:error, reason} ->
          Logger.warning(
            "Cache read error: #{inspect(reason)}, falling back to Capway SOAP API"
          )

          fetch_and_cache(arguments, context, options, today)
      end
    end
  end

  @impl true
  def compensate(_error, _arguments, _context, _options) do
    :retry
  end

  @impl true
  def undo(_map, _context, _options, _step_options) do
    :ok
  end

  defp fetch_and_cache(arguments, context, options, today) do
    case CapwaySubscribers.run(arguments, context, options) do
      {:ok, subscribers} ->
        case CapwayCacheRepository.write_cache(today, subscribers) do
          :ok ->
            Logger.info("Cached #{length(subscribers)} subscribers for #{today}")

          {:error, reason} ->
            Logger.warning("Failed to write cache for #{today}: #{inspect(reason)}")
        end

        {:ok, subscribers}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
