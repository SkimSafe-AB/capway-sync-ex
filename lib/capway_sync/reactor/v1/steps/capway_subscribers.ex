defmodule CapwaySync.Reactor.V1.Steps.CapwaySubscribers do
  @moduledoc """
  Reactor step that fetches the complete Capway contract report over SOAP.

  ## Why the fetch is shaped the way it is

  The report (`CAP_q_contracts_skimsafe`) is paginated with `offset`/`maxrows`
  and returns **one row per contract**. Every row carries a `counter` column
  holding the row count of the *whole* report (see
  `ResponseHandler.report_total/1`), so the fetch knows its exact size up
  front and never has to guess where the report ends:

    1. The first page (`[0, @page_size)`) is fetched alone and the report
       total is read from it. An empty first page is an empty report.
    2. `@worker_count` workers fetch the remaining `[@page_size, total)` rows
       in parallel, page by page. A worker still stops early after a short
       non-empty page or two consecutive empty pages, so a report that turns
       out shorter than its counter does not cost a sweep of empty pages.
    3. Every page is recorded as a `Page` (offset, requested, rows) and the
       whole set is validated: once a short or empty page has been seen no
       later offset may return rows (`validate_page_sequence/1`), and the
       fetched rows must add up to the counter (`validate_row_count/2`).
    4. One probe at offset `total` must return no rows
       (`confirm_report_end/3`) — a counter that undercounts would otherwise
       silently truncate the snapshot.

  Any failure — a worker error, a worker killed by the task timeout, an
  inconsistent page sequence, a row-count mismatch, rows past the counter —
  makes the step return `{:error, _}` so the reactor retries (`compensate/4`
  → `:retry`) rather than handing a partial snapshot to `CompareDataV2`, where
  every Trinity subscriber whose contract fell in the missing range would
  become a false `:capway_create_contract` action item.

  When `CAPWAY_MAX_PAGES` is set the fetch is intentionally truncated for
  development: the total is capped and the end-of-report probe is skipped.
  """

  use Reactor.Step
  alias CapwaySync.Soap.GenerateReport
  alias CapwaySync.Soap.ResponseHandler
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
  tested without SOAP.
  """
  @type fetch_page_fun ::
          (non_neg_integer(), pos_integer() -> {:ok, [CapwaySubscriber.t()]} | {:error, term()})

  @typedoc """
  Same as `fetch_page_fun`, plus a label for log lines and the debug dump.
  Production uses `fetch_page_with_retry/3`.
  """
  @type labelled_fetch_fun ::
          (non_neg_integer(), pos_integer(), String.t() ->
             {:ok, [CapwaySubscriber.t()]} | {:error, term()})

  @doc "Rows requested per SOAP page (Capway caps a page at 100)."
  @spec page_size() :: pos_integer()
  def page_size, do: @page_size

  @impl true
  def run(_map, _context, _options) do
    reset_debug_file()
    max_pages = Application.get_env(:capway_sync, :capway_max_pages)
    Logger.info("Starting Capway subscriber fetch (#{@worker_count} workers after the first page)")

    case fetch_pages(max_pages, &fetch_page_with_retry/3) do
      {:ok, pages, total} ->
        subscribers = subscribers_from_pages(pages)
        log_fetch_summary(subscribers, total)
        {:ok, subscribers}

      {:error, reason} ->
        Logger.error("Failed to fetch Capway subscribers: #{inspect(reason)}")
        {:error, "Failed to fetch capway subscribers: #{inspect(reason)}"}
    end
  end

  @doc """
  Runs the whole paged fetch with an injectable page fetcher.

  Returns `{:ok, pages, total}` — every fetched `Page` plus the report total
  read from the counter column — or `{:error, reason}`. `max_pages` is the
  `CAPWAY_MAX_PAGES` cap (`nil`/`0` = unlimited).

  Made public so the orchestration (first page → total → workers →
  validation → end probe) can be tested without SOAP; `run/3` is a thin
  wrapper around it.
  """
  @spec fetch_pages(non_neg_integer() | nil, labelled_fetch_fun()) ::
          {:ok, [Page.t()], non_neg_integer()} | {:error, term()}
  def fetch_pages(max_pages, fetch_fun) do
    with {:ok, first_page, total} <- fetch_first_page(&fetch_fun.(&1, &2, "first")),
         limited_total = apply_page_limit(total, max_pages),
         {:ok, worker_pages} <-
           fetch_with_parallel_workers(
             first_page.requested,
             limited_total - first_page.requested,
             fetch_fun
           ),
         pages = [first_page | worker_pages],
         :ok <- validate_page_sequence(pages),
         :ok <- validate_row_count(pages, limited_total),
         :ok <- maybe_confirm_report_end(total, limited_total, &fetch_fun.(&1, &2, "probe")) do
      {:ok, pages, total}
    end
  end

  @doc """
  Fetches the first report page and reads the report total from its
  `counter` column.

  Returns `{:ok, page, total}`. An empty first page is an empty report
  (`total` 0). A non-empty page whose rows carry no usable counter returns
  `{:error, {:invalid_report_total, reason}}` (see
  `ResponseHandler.report_total/1`); a fetch failure returns
  `{:error, {:first_page_error, reason}}`.
  """
  @spec fetch_first_page(fetch_page_fun()) ::
          {:ok, Page.t(), non_neg_integer()} | {:error, term()}
  def fetch_first_page(fetch_fun) do
    case fetch_fun.(0, @page_size) do
      {:ok, []} ->
        Logger.warning("⚠️ First page: the Capway report returned no rows at all")
        {:ok, %Page{offset: 0, requested: @page_size, subscribers: []}, 0}

      {:ok, subscribers} ->
        page = %Page{offset: 0, requested: @page_size, subscribers: subscribers}
        log_page("First page", page)

        case ResponseHandler.report_total(subscribers) do
          {:ok, total} ->
            Logger.info("Capway report counter: #{total} rows in total")
            {:ok, page, total}

          {:error, reason} ->
            Logger.error(
              "❌ Cannot read the report total from the counter column: #{inspect(reason)}"
            )

            {:error, {:invalid_report_total, reason}}
        end

      {:error, reason} ->
        {:error, {:first_page_error, reason}}
    end
  end

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

  # Fetches `row_count` rows from `start_offset` with parallel workers. The
  # first page has already been fetched, so a report that fits in one page
  # needs no workers at all.
  defp fetch_with_parallel_workers(_start_offset, row_count, _fetch_fun) when row_count <= 0 do
    Logger.info("The first page covers the whole report — no parallel workers needed")
    {:ok, []}
  end

  defp fetch_with_parallel_workers(start_offset, row_count, fetch_fun) do
    ranges = calculate_worker_ranges(start_offset, row_count, @worker_count)
    Logger.info("Worker ranges: #{inspect(ranges)}")
    timeout = max(15 * row_count * 100, @min_worker_timeout_ms)
    Logger.info("Setting timeout to #{timeout}ms for fetching #{row_count} records")

    tasks =
      ranges
      |> Enum.with_index(1)
      |> Task.async_stream(
        fn {{offset, count}, worker_id} ->
          fetch_worker_pages(
            worker_id,
            offset,
            count,
            &fetch_fun.(&1, &2, "worker-#{worker_id}")
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
  Splits `row_count` rows starting at `start_offset` into `worker_count`
  `{offset, count}` ranges of (near) equal size; the first workers absorb the
  remainder and empty ranges are dropped.

  Made public for testing purposes.
  """
  @spec calculate_worker_ranges(non_neg_integer(), non_neg_integer(), pos_integer()) ::
          [{non_neg_integer(), pos_integer()}]
  def calculate_worker_ranges(start_offset, row_count, worker_count) do
    base_size = div(row_count, worker_count)
    remainder = rem(row_count, worker_count)

    Enum.reduce(0..(worker_count - 1), [], fn worker_index, acc ->
      # First workers get an extra record if there's a remainder
      extra = if worker_index < remainder, do: 1, else: 0
      worker_size = base_size + extra

      # Calculate offset based on previous workers
      offset = start_offset + worker_index * base_size + min(worker_index, remainder)

      [{offset, worker_size} | acc]
    end)
    |> Enum.reverse()
    |> Enum.reject(fn {_offset, size} -> size == 0 end)
  end

  @doc """
  Fetches `count` rows starting at `offset` for one worker, one page at a time.

  Returns `{:ok, {worker_id, [Page.t()]}}` or `{:error, {worker_id, reason}}`
  on the first page that fails after retries.

  The ranges are sized from the report's own counter, which should be exact.
  Should the report nevertheless turn out *shorter* than the counter, a
  worker stops early — without fetching the rest of its range — as soon as
  it has seen the end of the report:

    * a **short, non-empty** page (fewer rows than requested), or
    * **two consecutive empty** pages.

  A single empty page is recorded (and logged) and the worker continues, so
  `validate_page_sequence/1` can tell a silently failed page (data follows)
  from the genuine end of the report (only empty pages follow).

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
        log_page("Worker #{worker_id}", page)
        pages = [page | acc]

        if end_of_report?(pages) do
          Logger.info(
            "Worker #{worker_id}: End of report reached at offset #{offset} — " <>
              "skipping the remaining #{remaining - chunk_size} records of the range"
          )

          do_fetch_worker_pages(worker_id, offset, 0, fetch_fun, pages)
        else
          do_fetch_worker_pages(
            worker_id,
            offset + chunk_size,
            remaining - chunk_size,
            fetch_fun,
            pages
          )
        end

      {:error, reason} ->
        {:error, {worker_id, reason}}
    end
  end

  # `pages` is newest-first. The end of the report is certain after a short
  # non-empty page, or after two consecutive empty pages.
  defp end_of_report?([%Page{subscribers: [_ | _]} = latest | _]), do: Page.short?(latest)
  defp end_of_report?([%Page{subscribers: []}, %Page{subscribers: []} | _]), do: true
  defp end_of_report?(_pages), do: false

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
  Checks that the rows fetched across all pages add up to `expected` — the
  report counter, capped by `CAPWAY_MAX_PAGES`.

  Fewer rows means a page silently lost rows or the counter overstates the
  report; more rows means the counter understates it. Either way the snapshot
  is refused with `{:error, {:row_count_mismatch, details}}`.
  """
  @spec validate_row_count([Page.t()], non_neg_integer()) ::
          :ok | {:error, {:row_count_mismatch, map()}}
  def validate_row_count(pages, expected) when is_list(pages) do
    fetched = row_count(pages)

    if fetched == expected do
      :ok
    else
      Logger.error(
        "❌ Capway row count mismatch: the report counter says #{expected} rows but " <>
          "#{fetched} were fetched. Refusing the snapshot to avoid false " <>
          ":capway_create_contract action items."
      )

      {:error, {:row_count_mismatch, %{expected: expected, fetched: fetched}}}
    end
  end

  @doc """
  Probes offset `total` once; the report must have no rows there.

  Rows past the counter would mean the counter undercounts the report and the
  fetch stopped too early. Returns `:ok`,
  `{:error, {:rows_past_counter, details}}` or
  `{:error, {:probe_error, offset, reason}}`.

  Made public so it can be tested with an injected `fetch_fun`.
  """
  @spec confirm_report_end(non_neg_integer(), pos_integer(), fetch_page_fun()) ::
          :ok | {:error, term()}
  def confirm_report_end(total, page_size \\ @page_size, fetch_fun) do
    case fetch_fun.(total, page_size) do
      {:ok, []} ->
        Logger.info("End-of-report probe at offset #{total} returned no rows — counter confirmed")
        :ok

      {:ok, subscribers} ->
        details = %{counter: total, probe_offset: total, probe_fetched: length(subscribers)}

        Logger.error(
          "❌ Capway report has rows past its counter: offset #{total} still returned " <>
            "#{length(subscribers)} rows. Refusing the snapshot to avoid false " <>
            ":capway_create_contract action items."
        )

        {:error, {:rows_past_counter, details}}

      {:error, reason} ->
        {:error, {:probe_error, total, reason}}
    end
  end

  defp maybe_confirm_report_end(0, _limited_total, _fetch_fun) do
    Logger.info("Empty report — skipping the end-of-report probe")
    :ok
  end

  defp maybe_confirm_report_end(total, limited_total, _fetch_fun) when limited_total < total do
    Logger.info(
      "CAPWAY_MAX_PAGES truncated the fetch to #{limited_total}/#{total} rows — " <>
        "skipping the end-of-report probe"
    )

    :ok
  end

  defp maybe_confirm_report_end(total, _limited_total, fetch_fun),
    do: confirm_report_end(total, @page_size, fetch_fun)

  defp row_count(pages), do: pages |> Enum.map(&Page.fetched/1) |> Enum.sum()

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

  defp log_fetch_summary(subscribers, total) do
    nil_contract_count = Enum.count(subscribers, &is_nil(&1.contract_ref_no))

    Logger.info(
      "Successfully fetched #{length(subscribers)} total subscribers " <>
        "(report counter: #{total}, #{nil_contract_count} with nil contract_ref_no)"
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

  # Clear the previous run's debug dump.
  defp reset_debug_file do
    file_dir = System.get_env("CAPWAY_DEBUG_FILE_DIR") || "priv"
    File.write(Path.join(file_dir, "soap_response.xml"), "")
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
