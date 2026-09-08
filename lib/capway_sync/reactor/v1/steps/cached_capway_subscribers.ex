defmodule CapwaySync.Reactor.V1.Steps.CachedCapwaySubscribers do
  @moduledoc """
  Reactor step that wraps `CapwaySubscribers` with a DynamoDB cache layer.

  Capway's SOAP API is slow and only updates once per day. This step checks
  the cache first and only falls through to the SOAP API on a cache miss
  or when bypass is enabled via `CAPWAY_CACHE_BYPASS=true`.

  ## Snapshot-shrink guard

  Before a freshly fetched snapshot is cached and handed on, its size is
  compared with the most recent previous day's cached snapshot (the cache
  manifest keeps `total_subscribers`; entries live for two days). If today's
  count is more than `drop_tolerance/0` below the previous count the step
  returns `{:error, {:snapshot_shrunk, details}}` **without** writing the
  cache, so the reactor retries and, if Capway keeps returning a truncated
  report, the whole workflow fails instead of emitting a
  `:capway_create_contract` item for every contract that went missing.

  The tolerance is a fraction, configured via `CAPWAY_SNAPSHOT_DROP_TOLERANCE`
  (`:capway_sync, :capway_snapshot_drop_tolerance`), default `0.05` (5 %).
  Set it to `1.0` to disable the guard. Genuine daily churn (cancellations)
  is far below 5 % of the contract base; a real drop of that size deserves a
  human look anyway.
  """

  use Reactor.Step

  alias CapwaySync.Reactor.V1.Steps.CapwaySubscribers
  alias CapwaySync.Dynamodb.CapwayCacheRepository

  require Logger

  @default_drop_tolerance 0.05
  # The cache TTL is 2 days, so at most two earlier manifests can exist.
  @lookback_days 2

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
          Logger.warning("Cache read error: #{inspect(reason)}, falling back to Capway SOAP API")

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

  @doc """
  Maximum tolerated fractional drop of today's snapshot size versus the
  previous day's cached snapshot (e.g. `0.05` = 5 %).
  """
  @spec drop_tolerance() :: float()
  def drop_tolerance do
    case Application.get_env(:capway_sync, :capway_snapshot_drop_tolerance) do
      value when is_number(value) and value >= 0 -> value / 1
      _ -> @default_drop_tolerance
    end
  end

  @doc """
  True when `current_count` is more than `tolerance` (a fraction) below
  `previous_count`. Never true when there is no meaningful previous count.
  """
  @spec snapshot_shrunk?(non_neg_integer(), non_neg_integer() | nil, number()) :: boolean()
  def snapshot_shrunk?(current_count, previous_count, tolerance)
      when is_integer(previous_count) and previous_count > 0 do
    current_count < previous_count * (1 - tolerance)
  end

  def snapshot_shrunk?(_current_count, _previous_count, _tolerance), do: false

  @doc """
  Checks a freshly fetched snapshot against the most recent earlier cached
  snapshot. Returns `:ok` when there is nothing to compare against or the
  size is within tolerance, otherwise `{:error, {:snapshot_shrunk, details}}`.

  `previous_lookup` receives an ISO date string and must return
  `{:ok, %{total_subscribers: n}}`, `{:miss}` or `{:error, _}`; it defaults
  to `CapwayCacheRepository.read_manifest/1` and is injectable for tests.
  """
  @spec guard_against_shrunken_snapshot(list(), String.t(), (String.t() -> term())) ::
          :ok | {:error, {:snapshot_shrunk, map()}}
  def guard_against_shrunken_snapshot(
        subscribers,
        today,
        previous_lookup \\ &CapwayCacheRepository.read_manifest/1
      ) do
    current = length(subscribers)

    case previous_snapshot_count(today, previous_lookup) do
      nil ->
        Logger.info("No previous Capway snapshot to compare #{current} fetched rows against")
        :ok

      {previous_date, previous} ->
        tolerance = drop_tolerance()

        if snapshot_shrunk?(current, previous, tolerance) do
          details = %{
            current: current,
            previous: previous,
            previous_date: previous_date,
            tolerance: tolerance
          }

          Logger.error(
            "❌ Capway snapshot shrunk: fetched #{current} rows today but #{previous} were " <>
              "cached on #{previous_date} (tolerance #{tolerance * 100}%). Refusing to cache " <>
              "or use this snapshot to avoid false :capway_create_contract action items."
          )

          {:error, {:snapshot_shrunk, details}}
        else
          Logger.info(
            "Capway snapshot size check passed: #{current} rows today vs #{previous} on #{previous_date}"
          )

          :ok
        end
    end
  end

  defp previous_snapshot_count(today, previous_lookup) do
    today_date = Date.from_iso8601!(today)

    Enum.find_value(1..@lookback_days, fn days_ago ->
      date = today_date |> Date.add(-days_ago) |> Date.to_string()

      case previous_lookup.(date) do
        {:ok, %{total_subscribers: count}} when is_integer(count) and count > 0 -> {date, count}
        _ -> nil
      end
    end)
  end

  defp fetch_and_cache(arguments, context, options, today) do
    with {:ok, subscribers} <- CapwaySubscribers.run(arguments, context, options),
         :ok <- guard_against_shrunken_snapshot(subscribers, today) do
      case CapwayCacheRepository.write_cache(today, subscribers) do
        :ok ->
          Logger.info("Cached #{length(subscribers)} subscribers for #{today}")

        {:error, reason} ->
          Logger.warning("Failed to write cache for #{today}: #{inspect(reason)}")
      end

      {:ok, subscribers}
    end
  end
end
