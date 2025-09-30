defmodule CapwaySync.Reactor.V1.Steps.CapwaySubscribers do
  use Reactor.Step
  alias CapwaySync.Soap.GenerateReport
  alias CapwaySync.Soap.ResponseHandler
  alias CapwaySync.Rest.{AccessToken, CustomerCount}
  require Logger

  @worker_count 2

  @impl true
  def run(_map, _context, _options) do
    Logger.info("Starting parallel Capway subscriber fetch with #{@worker_count} workers")

    with {:ok, access_token} <- AccessToken.run(),
         {:ok, total_count} <- CustomerCount.run(access_token),
         {:ok, all_subscribers} <- fetch_with_parallel_workers(total_count) do
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

  # Fetch subscribers using 4 parallel workers that divide the total count.
  # Each worker uses SOAP generate_report with pagination (offset/maxrows).
  defp fetch_with_parallel_workers(total_count) do
    ranges = calculate_worker_ranges(total_count, @worker_count)
    Logger.info("Worker ranges: #{inspect(ranges)}")

    # Create tasks for each worker
    tasks =
      ranges
      |> Enum.with_index(1)
      |> Task.async_stream(
        fn {{offset, maxrows}, worker_id} ->
          fetch_worker_data(worker_id, offset, maxrows)
        end,
        max_concurrency: @worker_count,
        timeout: 60_000,
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

    case GenerateReport.generate_report(
           "CAP_q_contracts_skimsafe",
           "Data",
           [%{name: "creditor", value: "202623"}],
           offset: current_offset,
           maxrows: chunk_size
         ) do
      {:ok, xml_data} ->
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

          {:error, reason} ->
            Logger.error(
              "Worker #{worker_id}: Failed to parse XML at offset #{current_offset} - #{inspect(reason)}"
            )

            {:error, {worker_id, {:parse_error, reason}}}
        end

      {:error, reason} ->
        Logger.error(
          "Worker #{worker_id}: Failed to fetch chunk at offset #{current_offset} - #{inspect(reason)}"
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

  @impl true
  def compensate(_error, _arguments, _context, _options) do
    :retry
  end

  @impl true
  def undo(_map, _context, _options, _step_options) do
    :ok
  end
end
