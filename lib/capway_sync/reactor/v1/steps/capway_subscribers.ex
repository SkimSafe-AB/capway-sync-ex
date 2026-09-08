defmodule CapwaySync.Reactor.V1.Steps.CapwaySubscribers do
  @moduledoc """
  Reactor step that fetches the complete Capway contract report over SOAP.

  ## Why the fetch is shaped the way it is

  The report (`CAP_q_contracts_skimsafe`) is paginated with `offset`/`maxrows`
  and returns **one row per contract**. The only cheap "how many rows are
  there" signal we have is the REST customer count, which counts *customers*,
  not contracts — a customer with several contracts produces more rows than
  the count suggests. The count is therefore treated as a **parallelisation
  hint**, never as the upper bound of the fetch:

    1. `@worker_count` workers fetch `[0, customer_count)` in parallel, page by
       page (`@page_size` rows each).
    2. A sequential **tail sweep** then continues from `customer_count` until
       the report returns a short page (fewer rows than requested). An empty
       page is confirmed with one extra probe so a single glitchy empty
       response cannot end the sweep early.
    3. Every page is recorded as a `Page` (offset, requested, rows) and the
       whole sequence is validated: once a short or empty page has been seen,
       no later offset may return rows. A page that silently came back empty
       in the middle of the report therefore fails the step instead of
       quietly dropping up to `@page_size` contracts.

  Any failure — a worker error, a worker killed by the task timeout, an
  inconsistent page sequence, a tail-sweep error — makes the step return
  `{:error, _}` so the reactor retries (`compensate/4` → `:retry`) rather than
  handing a partial snapshot to `CompareDataV2`, where every Trinity
  subscriber whose contract fell in the missing range would become a false
  `:capway_create_contract` action item.

  When `CAPWAY_MAX_PAGES` is set the fetch is intentionally truncated for
  development, and the tail sweep is skipped.
  """

  use Reactor.Step
  alias CapwaySync.Soap.GenerateReport
  alias CapwaySync.Soap.ResponseHandler
  alias CapwaySync.Rest.{AccessToken, CustomerCount}
  alias CapwaySync.Models.CapwaySubscriber
  require Logger

  @worker_count 3
  @page_size 100
  @max_retries 3
  @report_name "CAP_q_contracts_skimsafe"
  @min_worker_timeout_ms 60_000

  defmodule Page do
    @moduledoc """
    One fetched report page: the offset and row count that were requested and
    the subscriber rows that actually came back.
    """

    @enforce_keys [:offset, :requested, :subscribers]
    defstruct [:offset, :requested, :subscribers]

    @type t :: %__MODULE__{
            offset: non_neg_integer(),
            requested: pos_integer(),
            subscribers: [CapwaySubscriber.t()]
          }

    @doc "Number of rows the page actually contained."
    @spec fetched(t()) :: non_neg_integer()
    def fetched(%__MODULE__{subscribers: subscribers}), do: length(subscribers)

    @doc "True when the page returned fewer rows than requested (end-of-data signal)."
    @spec short?(t()) :: boolean()
    def short?(%__MODULE__{} = page), do: fetched(page) < page.requested
  end

  @typedoc """
  Fetches one report page. Injected into the page loops so they can be unit
  tested without SOAP; production uses `fetch_page_with_retry/3`.
  """
  @type fetch_page_fun ::
          (non_neg_integer(), pos_integer() -> {:ok, [CapwaySubscriber.t()]} | {:error, term()})

  @doc "Rows requested per SOAP page (Capway caps a page at 100)."
  @spec page_size() :: pos_integer()
  def page_size, do: @page_size

  @impl true
  def run(_map, _context, _options) do
    # Clear previous debug file
    file_dir = System.get_env("CAPWAY_DEBUG_FILE_DIR") || "priv"
    file_path = Path.join(file_dir, "soap_response.xml")
    File.write(file_path, "")

    Logger.info("Starting parallel Capway subscriber fetch with #{@worker_count} workers")

    max_pages = Application.get_env(:capway_sync, :capway_max_pages)

    with {:ok, access_token} <- AccessToken.run(),
         {:ok, customer_count} <- CustomerCount.run(access_token),
         limited_count = apply_page_limit(customer_count, max_pages),
         {:ok, worker_pages} <- fetch_with_parallel_workers(limited_count),
         {:ok, tail_pages} <- maybe_fetch_tail(limited_count, max_pages),
         pages = worker_pages ++ tail_pages,
         :ok <- validate_page_sequence(pages) do
      subscribers = subscribers_from_pages(pages)
      log_fetch_summary(subscribers, customer_count, tail_pages)
      {:ok, subscribers}
    else
      {:error, reason} ->
        Logger.error("Failed to fetch Capway subscribers: #{inspect(reason)}")
        {:error, "Failed to fetch capway subscribers: #{inspect(reason)}"}
    end
  end

  # Apply page limit to total count if configured
  defp apply_page_limit(total_count, nil), do: total_count
  defp apply_page_limit(total_count, 0), do: total_count

  defp apply_page_limit(total_count, max_pages) when max_pages > 0 do
    max_records = max_pages * @page_size
    limited = min(total_count, max_records)

    if limited < total_count do
      Logger.warning(
        "⚠️ Limiting Capway fetch to #{max_pages} pages (#{limited} records) out of #{total_count} total records"
      )
    end

    limited
  end

  defp apply_page_limit(total_count, _), do: total_count

  # The tail sweep exists to pick up rows beyond the REST customer count. When
  # a page limit is configured the truncation is intentional, so skip it.
  defp maybe_fetch_tail(_limited_count, max_pages) when is_integer(max_pages) and max_pages > 0 do
    Logger.info("CAPWAY_MAX_PAGES is set (#{max_pages}) — skipping tail sweep")
    {:ok, []}
  end

  defp maybe_fetch_tail(start_offset, _max_pages) do
    Logger.info("Starting tail sweep from offset #{start_offset} (past the REST customer count)")
    fetch_tail(start_offset, @page_size, &fetch_page_with_retry(&1, &2, "tail"))
  end

  # Fetch pages using parallel workers that divide the customer count.
  defp fetch_with_parallel_workers(total_count) do
    ranges = calculate_worker_ranges(total_count, @worker_count)
    Logger.info("Worker ranges: #{inspect(ranges)}")
    timeout = max(15 * total_count * 100, @min_worker_timeout_ms)
    Logger.info("Setting timeout to #{timeout}ms for fetching #{total_count} records")

    tasks =
      ranges
      |> Enum.with_index(1)
      |> Task.async_stream(
        fn {{offset, count}, worker_id} ->
          fetch_worker_pages(
            worker_id,
            offset,
            count,
            &fetch_page_with_retry(&1, &2, "worker-#{worker_id}")
          )
        end,
        max_concurrency: @worker_count,
        timeout: timeout,
        on_timeout: :kill_task
      )
      |> Enum.to_list()

    merge_worker_results(tasks)
  end

  @doc """
  Calculate offset and maxrows for each worker to divide the work evenly.
  Made public for testing purposes.
  """
  def calculate_worker_ranges(total_count, worker_count) do
    base_size = div(total_count, worker_count)
    remainder = rem(total_count, worker_count)

    Enum.reduce(0..(worker_count - 1), [], fn worker_index, acc ->
      # First workers get an extra record if there's a remainder
      extra = if worker_index < remainder, do: 1, else: 0
      worker_size = base_size + extra

      # Calculate offset based on previous workers
      offset = worker_index * base_size + min(worker_index, remainder)

      [{offset, worker_size} | acc]
    end)
    |> Enum.reverse()
    |> Enum.reject(fn {_offset, size} -> size == 0 end)
  end

  @doc """
  Fetches `count` rows starting at `offset` for one worker, one page at a time.

  Returns `{:ok, {worker_id, [Page.t()]}}` when every page was fetched, or
  `{:error, {worker_id, reason}}` on the first page that fails after retries.
  A page that comes back empty is recorded (and logged) but not treated as an
  error here — `validate_page_sequence/1` decides afterwards whether it was a
  legitimate end of data or a silently failed page.

  Made public so the page loop can be tested with an injected `fetch_fun`.
  """
  @spec fetch_worker_pages(term(), non_neg_integer(), non_neg_integer(), fetch_page_fun()) ::
          {:ok, {term(), [Page.t()]}} | {:error, {term(), term()}}
  def fetch_worker_pages(worker_id, offset, count, fetch_fun) do
    Logger.info("Worker #{worker_id}: Fetching #{count} records starting at offset #{offset}")
    do_fetch_worker_pages(worker_id, offset, count, fetch_fun, [])
  end

  defp do_fetch_worker_pages(worker_id, _offset, remaining, _fetch_fun, acc)
       when remaining <= 0 do
    pages = Enum.reverse(acc)
    total_fetched = pages |> Enum.map(&Page.fetched/1) |> Enum.sum()
    Logger.info("Worker #{worker_id}: Completed fetching #{total_fetched} total subscribers")
    {:ok, {worker_id, pages}}
  end

  defp do_fetch_worker_pages(worker_id, offset, remaining, fetch_fun, acc) do
    chunk_size = min(remaining, @page_size)

    Logger.info(
      "Worker #{worker_id}: Fetching chunk of #{chunk_size} records at offset #{offset}"
    )

    case fetch_fun.(offset, chunk_size) do
      {:ok, subscribers} ->
        page = %Page{offset: offset, requested: chunk_size, subscribers: subscribers}
        log_page(worker_id, page)

        do_fetch_worker_pages(worker_id, offset + chunk_size, remaining - chunk_size, fetch_fun, [
          page | acc
        ])

      {:error, reason} ->
        {:error, {worker_id, reason}}
    end
  end

  defp log_page(label, %Page{} = page) do
    fetched = Page.fetched(page)

    if fetched == 0 do
      Logger.warning(
        "⚠️ #{label}: Got 0 subscribers from offset=#{page.offset}, chunk_size=#{page.requested}. " <>
          "Whether this is the end of the report is decided by the page-sequence validation."
      )
    else
      Logger.info(
        "#{label}: Fetched #{fetched}/#{page.requested} subscribers at offset=#{page.offset}"
      )
    end
  end

  @doc """
  Sequentially fetches pages from `start_offset` until the report signals the
  end of data.

    * A **short, non-empty** page ends the sweep.
    * An **empty** page is confirmed with one probe at the next offset. If the
      probe is also empty the sweep ends; if the probe returns rows the empty
      page was a silently failed request and the sweep returns
      `{:error, {:inconsistent_pages, details}}`.

  Returns `{:ok, [Page.t()]}` (possibly `[]` if nothing lies past
  `start_offset`... the terminating empty/short page is included) or
  `{:error, reason}`.

  Made public so it can be tested with an injected `fetch_fun`.
  """
  @spec fetch_tail(non_neg_integer(), pos_integer(), fetch_page_fun()) ::
          {:ok, [Page.t()]} | {:error, term()}
  def fetch_tail(start_offset, page_size \\ @page_size, fetch_fun) do
    do_fetch_tail(start_offset, page_size, fetch_fun, [])
  end

  defp do_fetch_tail(offset, page_size, fetch_fun, acc) do
    case fetch_fun.(offset, page_size) do
      {:ok, subscribers} ->
        page = %Page{offset: offset, requested: page_size, subscribers: subscribers}
        log_page("tail", page)

        cond do
          subscribers == [] ->
            confirm_end_of_report(page, page_size, fetch_fun, acc)

          Page.short?(page) ->
            {:ok, Enum.reverse([page | acc])}

          true ->
            do_fetch_tail(offset + page_size, page_size, fetch_fun, [page | acc])
        end

      {:error, reason} ->
        {:error, {:tail_fetch_error, offset, reason}}
    end
  end

  defp confirm_end_of_report(%Page{} = empty_page, page_size, fetch_fun, acc) do
    probe_offset = empty_page.offset + page_size

    case fetch_fun.(probe_offset, page_size) do
      {:ok, []} ->
        {:ok, Enum.reverse([empty_page | acc])}

      {:ok, subscribers} ->
        {:error,
         {:inconsistent_pages,
          %{
            short_offset: empty_page.offset,
            short_requested: empty_page.requested,
            short_fetched: 0,
            data_offset: probe_offset,
            data_fetched: length(subscribers)
          }}}

      {:error, reason} ->
        {:error, {:tail_fetch_error, probe_offset, reason}}
    end
  end

  @doc """
  Validates that the fetched pages form a consistent paginated report.

  Pages are sorted by offset. The first short or empty page marks the end of
  the report; any later page that still contains rows proves the short page
  was a silently failed request rather than the end of data.

  Returns `:ok` or `{:error, {:inconsistent_pages, details}}`.
  """
  @spec validate_page_sequence([Page.t()]) :: :ok | {:error, {:inconsistent_pages, map()}}
  def validate_page_sequence(pages) when is_list(pages) do
    sorted = Enum.sort_by(pages, & &1.offset)

    case Enum.split_while(sorted, &(not Page.short?(&1))) do
      {_full, []} ->
        :ok

      {_full, [end_page | later]} ->
        case Enum.find(later, &(Page.fetched(&1) > 0)) do
          nil ->
            :ok

          data_page ->
            details = %{
              short_offset: end_page.offset,
              short_requested: end_page.requested,
              short_fetched: Page.fetched(end_page),
              data_offset: data_page.offset,
              data_fetched: Page.fetched(data_page)
            }

            Logger.error(
              "❌ Inconsistent Capway page sequence: offset #{end_page.offset} returned " <>
                "#{Page.fetched(end_page)}/#{end_page.requested} rows but offset " <>
                "#{data_page.offset} still returned #{Page.fetched(data_page)} rows. " <>
                "Refusing the snapshot to avoid false :capway_create_contract action items."
            )

            {:error, {:inconsistent_pages, details}}
        end
    end
  end

  @doc """
  Flattens pages (sorted by offset) into the subscriber list.
  """
  @spec subscribers_from_pages([Page.t()]) :: [CapwaySubscriber.t()]
  def subscribers_from_pages(pages) do
    pages
    |> Enum.sort_by(& &1.offset)
    |> Enum.flat_map(& &1.subscribers)
  end

  @doc """
  Merges per-worker results into a single list, in worker-id order.

  Each successful worker contributes a list (of `Page.t()` in production; the
  function itself only concatenates). Returns `{:ok, items}` ONLY when every
  worker succeeded. If any worker errored or was killed by
  `Task.async_stream`'s timeout, returns `{:error, {:partial_fetch, failures}}`
  so the reactor retries the step instead of silently propagating an
  incomplete Capway snapshot. Returning partial data would poison the daily
  cache and cause false `:capway_create_contract` action items for every
  Trinity subscriber whose contract fell in the missing worker's offset range.

  Made public for direct unit testing of the fail-fast contract.
  """
  def merge_worker_results(task_results) do
    {successes, failures} =
      Enum.reduce(task_results, {[], []}, fn
        {:ok, {:ok, {worker_id, items}}}, {success_acc, failure_acc} ->
          {[{worker_id, items} | success_acc], failure_acc}

        {:ok, {:error, {worker_id, reason}}}, {success_acc, failure_acc} ->
          {success_acc, [{worker_id, reason} | failure_acc]}

        {:exit, reason}, {success_acc, failure_acc} ->
          {success_acc, [{:timeout, reason} | failure_acc]}
      end)

    Enum.each(successes, fn {worker_id, items} ->
      Logger.info("📊 Worker #{worker_id} result: #{length(items)} items fetched")
    end)

    case failures do
      [] ->
        merged =
          successes
          |> Enum.sort_by(fn {worker_id, _} -> worker_id end)
          |> Enum.flat_map(fn {_worker_id, items} -> items end)

        Logger.info("All #{length(successes)} workers succeeded, merged #{length(merged)} items")
        {:ok, merged}

      failures ->
        Logger.error(
          "❌ Capway fetch failed: #{length(failures)} worker(s) failed, " <>
            "#{length(successes)} succeeded. Refusing to return partial data to avoid " <>
            "false :capway_create_contract action items. Failures: #{inspect(failures)}"
        )

        {:error, {:partial_fetch, failures}}
    end
  end

  defp log_fetch_summary(subscribers, customer_count, tail_pages) do
    total = length(subscribers)
    nil_contract_count = Enum.count(subscribers, &is_nil(&1.contract_ref_no))
    tail_rows = tail_pages |> Enum.map(&Page.fetched/1) |> Enum.sum()

    Logger.info(
      "Successfully fetched #{total} total subscribers " <>
        "(REST customer count: #{customer_count}, rows found past the count: #{tail_rows}, " <>
        "#{nil_contract_count} with nil contract_ref_no)"
    )
  end

  @doc """
  Fetches and parses one report page with retries.

  `label` is used for log lines and the debug-dump filename. Retries
  `#{@max_retries}` times on both transport (`{:fetch_error, _}`) and parse
  (`{:parse_error, _}`) failures with a linear backoff, then returns the last
  error.
  """
  @spec fetch_page_with_retry(non_neg_integer(), pos_integer(), String.t()) ::
          {:ok, [CapwaySubscriber.t()]} | {:error, term()}
  def fetch_page_with_retry(offset, maxrows, label) do
    do_fetch_page_with_retry(offset, maxrows, label, @max_retries)
  end

  defp do_fetch_page_with_retry(offset, maxrows, label, retries_left) do
    case fetch_page(offset, maxrows, label) do
      {:ok, subscribers} ->
        {:ok, subscribers}

      {:error, {kind, reason}} when retries_left > 0 ->
        Logger.warning(
          "#{label}: #{describe_failure(kind)} at offset #{offset}, retrying... " <>
            "(#{retries_left} retries left) - #{inspect(reason)}"
        )

        Process.sleep(backoff_ms(kind, retries_left))
        do_fetch_page_with_retry(offset, maxrows, label, retries_left - 1)

      {:error, {kind, reason}} = error ->
        Logger.error(
          "#{label}: #{describe_failure(kind)} at offset #{offset} after all retries - #{inspect(reason)}"
        )

        error
    end
  end

  defp describe_failure(:parse_error), do: "Failed to parse XML"
  defp describe_failure(_), do: "Failed to fetch chunk"

  defp backoff_ms(:parse_error, retries_left), do: 1000 * (@max_retries + 1 - retries_left)
  defp backoff_ms(_kind, retries_left), do: 1500 * (@max_retries + 1 - retries_left)

  defp fetch_page(offset, maxrows, label) do
    case GenerateReport.generate_report(
           @report_name,
           "Data",
           [%{name: "creditor", value: creditor()}],
           offset: offset,
           maxrows: maxrows
         ) do
      {:ok, xml_data} ->
        append_to_debug_file(xml_data, label)

        case Saxy.parse_string(xml_data, ResponseHandler, []) do
          {:ok, subscribers} -> {:ok, subscribers}
          {:error, reason} -> {:error, {:parse_error, reason}}
        end

      {:error, reason} ->
        {:error, {:fetch_error, reason}}
    end
  end

  @doc """
  Creditor id for the Capway report query, sourced from config
  (`CAPWAY_CREDITOR` env var). Raises if unset so a misconfigured deploy fails
  loudly instead of querying Capway with a nil/blank creditor.

  Made public for testing purposes.
  """
  def creditor do
    case Application.get_env(:capway_sync, :capway_creditor) do
      value when is_binary(value) and value != "" ->
        value

      _ ->
        raise "CAPWAY_CREDITOR is not configured. Set the CAPWAY_CREDITOR env var to the Capway creditor id."
    end
  end

  # Append raw XML response to a per-label debug file.
  defp append_to_debug_file(xml_data, label) do
    file_dir = System.get_env("CAPWAY_DEBUG_FILE_DIR") || "priv"
    file_path = Path.join(file_dir, "soap_response-#{label}.xml")
    File.write(file_path, xml_data, [:append])
  end

  @impl true
  def compensate(_error, _arguments, _context, _options) do
    :retry
  end

  @impl true
  def undo(_map, _context, _options, _step_options) do
    :ok
  end
end
