defmodule CapwaySync.Reactor.V1.Steps.CapwaySubscribers do
  use Reactor.Step
  alias CapwaySync.Soap.GenerateReport
  alias CapwaySync.Soap.ResponseHandler
  alias CapwaySync.Rest.{AccessToken, CustomerCount}
  alias CapwaySync.Models.Subscribers.Canonical
  require Logger

  @worker_count 3

  @impl true
  def run(_map, _context, _options) do
    # Clear previous debug file
    File.write("priv/soap_response.xml", "")

    Logger.info("Starting parallel Capway subscriber fetch with #{@worker_count} workers")

    # Get max pages configuration
    max_pages = Application.get_env(:capway_sync, :capway_max_pages)

    with {:ok, access_token} <- AccessToken.run(),
         {:ok, total_count} <- CustomerCount.run(access_token),
         limited_count <- apply_page_limit(total_count, max_pages),
         {:ok, all_subscribers} <- fetch_with_parallel_workers(limited_count) do
      Logger.info(
        "Successfully fetched #{length(all_subscribers)} total subscribers using parallel workers"
      )

      {:ok, all_subscribers}
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
    # 100 records per page
    max_records = max_pages * 100
    limited = min(total_count, max_records)

    if limited < total_count do
      Logger.warning(
        "⚠️ Limiting Capway fetch to #{max_pages} pages (#{limited} records) out of #{total_count} total records"
      )
    end

    limited
  end

  defp apply_page_limit(total_count, _), do: total_count

  # Fetch subscribers using 4 parallel workers that divide the total count.
  # Each worker uses SOAP generate_report with pagination (offset/maxrows).
  defp fetch_with_parallel_workers(total_count) do
    ranges = calculate_worker_ranges(total_count, @worker_count)
    Logger.info("Worker ranges: #{inspect(ranges)}")
    timeout = 15 * total_count * 100
    Logger.info("Setting timeout to #{timeout}ms for fetching #{total_count} records")

    # Create tasks for each worker
    tasks =
      ranges
      |> Enum.with_index(1)
      |> Task.async_stream(
        fn {{offset, maxrows}, worker_id} ->
          fetch_worker_data(worker_id, offset, maxrows)
        end,
        max_concurrency: @worker_count,
        timeout: timeout,
        on_timeout: :kill_task
      )
      |> Enum.to_list()

    # Process results and merge
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

  # Fetch data for a single worker using SOAP generate_report with pagination.
  # Handles Capway's 100 record limit by making multiple requests if needed.
  defp fetch_worker_data(worker_id, start_offset, total_records) do
    Logger.info(
      "Worker #{worker_id}: Fetching #{total_records} records starting at offset #{start_offset}"
    )

    fetch_worker_data_chunked(worker_id, start_offset, total_records, 100, [])
  end

  # Recursively fetch data in chunks of max_chunk_size (100) until all records are retrieved
  defp fetch_worker_data_chunked(worker_id, _current_offset, 0, _max_chunk_size, acc) do
    # No more records to fetch
    total_fetched = acc |> List.flatten() |> length()
    Logger.info("Worker #{worker_id}: Completed fetching #{total_fetched} total subscribers")
    {:ok, {worker_id, List.flatten(acc)}}
  end

  defp fetch_worker_data_chunked(
         worker_id,
         current_offset,
         remaining_records,
         max_chunk_size,
         acc
       ) do
    # Determine how many records to fetch in this chunk
    chunk_size = min(remaining_records, max_chunk_size)

    Logger.info(
      "Worker #{worker_id}: Fetching chunk of #{chunk_size} records at offset #{current_offset}"
    )

    fetch_chunk_with_retry(
      worker_id,
      current_offset,
      chunk_size,
      remaining_records,
      max_chunk_size,
      acc,
      3
    )
  end

  defp fetch_chunk_with_retry(
         worker_id,
         current_offset,
         chunk_size,
         remaining_records,
         max_chunk_size,
         acc,
         retries_left
       ) do
    case GenerateReport.generate_report(
           "CAP_q_contracts_skimsafe",
           "Data",
           [
             %{name: "creditor", value: "202623"}
           ],
           offset: current_offset,
           maxrows: chunk_size
         ) do
      {:ok, xml_data} ->
        # Append raw XML to debug file
        append_to_debug_file(xml_data, current_offset, chunk_size, worker_id)

        case Saxy.parse_string(xml_data, ResponseHandler, []) do
          {:ok, subscribers} ->
            fetched_count = length(subscribers)

            Logger.info(
              "Worker #{worker_id}: Successfully fetched #{fetched_count} subscribers from chunk"
            )

            # Continue fetching remaining records
            new_offset = current_offset + chunk_size
            new_remaining = remaining_records - chunk_size

            fetch_worker_data_chunked(worker_id, new_offset, new_remaining, max_chunk_size, [
              subscribers | acc
            ])

          {:error, reason} when retries_left > 0 ->
            Logger.warning(
              "Worker #{worker_id}: Failed to parse XML at offset #{current_offset}, retrying... (#{retries_left} retries left) - #{inspect(reason)}"
            )

            Process.sleep(1000 * (4 - retries_left))

            fetch_chunk_with_retry(
              worker_id,
              current_offset,
              chunk_size,
              remaining_records,
              max_chunk_size,
              acc,
              retries_left - 1
            )

          {:error, reason} ->
            Logger.error(
              "Worker #{worker_id}: Failed to parse XML at offset #{current_offset} after all retries - #{inspect(reason)}"
            )

            {:error, {worker_id, {:parse_error, reason}}}
        end

      {:error, reason} when retries_left > 0 ->
        Logger.warning(
          "Worker #{worker_id}: Failed to fetch chunk at offset #{current_offset}, retrying... (#{retries_left} retries left) - #{inspect(reason)}"
        )

        Process.sleep(1500 * (4 - retries_left))

        fetch_chunk_with_retry(
          worker_id,
          current_offset,
          chunk_size,
          remaining_records,
          max_chunk_size,
          acc,
          retries_left - 1
        )

      {:error, reason} ->
        Logger.error(
          "Worker #{worker_id}: Failed to fetch chunk at offset #{current_offset} after all retries - #{inspect(reason)}"
        )

        {:error, {worker_id, {:fetch_error, reason}}}
    end
  end

  # Merge results from all workers, handling both successes and failures.
  defp merge_worker_results(task_results) do
    {successes, failures} =
      Enum.reduce(task_results, {[], []}, fn
        {:ok, {:ok, {worker_id, subscribers}}}, {success_acc, failure_acc} ->
          {[{worker_id, subscribers} | success_acc], failure_acc}

        {:ok, {:error, {worker_id, reason}}}, {success_acc, failure_acc} ->
          {success_acc, [{worker_id, reason} | failure_acc]}

        {:exit, reason}, {success_acc, failure_acc} ->
          {success_acc, [{:timeout, reason} | failure_acc]}
      end)

    case failures do
      [] ->
        # All workers succeeded, merge the data
        all_subscribers =
          successes
          |> Enum.sort_by(fn {worker_id, _} -> worker_id end)
          |> Enum.flat_map(fn {_worker_id, subscribers} -> subscribers end)

        Logger.info(
          "All #{length(successes)} workers succeeded, merged #{length(all_subscribers)} total subscribers"
        )

        {:ok, all_subscribers}

      failures ->
        # Some workers failed
        success_count = length(successes)
        failure_count = length(failures)

        Logger.error(
          "#{failure_count} workers failed, #{success_count} succeeded. Failures: #{inspect(failures)}"
        )

        if success_count > 0 do
          # Partial success - return what we have but log warnings
          all_subscribers =
            successes
            |> Enum.sort_by(fn {worker_id, _} -> worker_id end)
            |> Enum.flat_map(fn {_worker_id, subscribers} -> subscribers end)

          Logger.warning(
            "Returning partial data: #{length(all_subscribers)} subscribers from #{success_count} successful workers"
          )

          {:ok, all_subscribers}
        else
          # Complete failure
          {:error, {:all_workers_failed, failures}}
        end
    end
  end

  # Append raw XML response to debug file for debugging purposes
  defp append_to_debug_file(xml_data, _offset, _maxrows, write_id) do
    filepath = "priv/soap_response-#{write_id}.xml"
    # Append raw XML directly to file
    File.write(filepath, xml_data, [:append])
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
