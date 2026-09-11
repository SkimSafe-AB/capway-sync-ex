defmodule CapwaySync.Reactor.V1.Steps.CapwaySubscribersTest do
  @moduledoc """
  Unit tests for the `CapwaySubscribers` fetch: `merge_worker_results/1`, the
  page loops, the counter-driven orchestration (`fetch_pages/2`) and the
  validations that refuse an incomplete snapshot.

  These tests pin the fail-fast contract: when ANY worker errors or is killed
  by `Task.async_stream`'s timeout, the step must return `{:error, ...}` so
  the reactor retries instead of writing a partial Capway snapshot to the
  daily cache. A partial snapshot would cause `get_contracts_to_create/3`
  (compare_data_v2.ex:182) to flag every Trinity subscriber whose contract
  fell into the missing worker's offset range as `:capway_create_contract`.
  """
  use ExUnit.Case, async: false
  import ExUnit.CaptureLog

  alias CapwaySync.Reactor.V1.Steps.CapwaySubscribers
  alias CapwaySync.Models.CapwaySubscriber

  # Every real report row ends with the `counter` column (the report-wide row
  # total); the helpers mirror that so `ResponseHandler.report_total/1` works.
  defp sub(contract_ref_no, counter \\ 6_137),
    do: %CapwaySubscriber{contract_ref_no: contract_ref_no, raw_data: ["0", nil, to_string(counter)]}

  defp ok(worker_id, subs), do: {:ok, {:ok, {worker_id, subs}}}
  defp err(worker_id, reason), do: {:ok, {:error, {worker_id, reason}}}
  defp timeout(reason), do: {:exit, reason}

  describe "merge_worker_results/1 — happy path" do
    test "merges all-success results in worker_id order" do
      results = [
        ok(2, [sub("ref-2a"), sub("ref-2b")]),
        ok(1, [sub("ref-1a")]),
        ok(3, [sub("ref-3a")])
      ]

      assert {:ok, merged} = CapwaySubscribers.merge_worker_results(results)
      assert Enum.map(merged, & &1.contract_ref_no) == ["ref-1a", "ref-2a", "ref-2b", "ref-3a"]
    end

    test "returns {:ok, []} when there are no results at all" do
      assert {:ok, []} = CapwaySubscribers.merge_worker_results([])
    end
  end

  describe "merge_worker_results/1 — fail-fast on any failure" do
    test "returns {:error, {:partial_fetch, _}} when one worker errors and others succeed" do
      results = [
        ok(1, [sub("ref-1a"), sub("ref-1b")]),
        err(2, {:fetch_error, :timeout}),
        ok(3, [sub("ref-3a")])
      ]

      log =
        capture_log(fn ->
          assert {:error, {:partial_fetch, failures}} =
                   CapwaySubscribers.merge_worker_results(results)

          assert [{2, {:fetch_error, :timeout}}] = failures
        end)

      assert log =~ "Refusing to return partial data"
    end

    test "returns {:error, {:partial_fetch, _}} when a worker is killed by Task timeout" do
      results = [
        ok(1, [sub("ref-1a")]),
        timeout(:killed),
        ok(3, [sub("ref-3a")])
      ]

      capture_log(fn ->
        assert {:error, {:partial_fetch, [{:timeout, :killed}]}} =
                 CapwaySubscribers.merge_worker_results(results)
      end)
    end

    test "returns {:error, {:partial_fetch, _}} when ALL workers fail" do
      results = [
        err(1, {:parse_error, :invalid_xml}),
        err(2, {:fetch_error, :econnrefused}),
        timeout(:timeout)
      ]

      capture_log(fn ->
        assert {:error, {:partial_fetch, failures}} =
                 CapwaySubscribers.merge_worker_results(results)

        assert length(failures) == 3
      end)
    end

    test "logs failure details so on-call can correlate with the run" do
      results = [
        ok(1, [sub("ref-1a")]),
        err(2, {:fetch_error, :nxdomain})
      ]

      log =
        capture_log(fn ->
          {:error, _} = CapwaySubscribers.merge_worker_results(results)
        end)

      assert log =~ "❌ Capway fetch failed"
      assert log =~ "1 worker(s) failed"
      assert log =~ "1 succeeded"
      assert log =~ "nxdomain"
    end

    test "does NOT silently return the successful workers' subscribers" do
      # Pre-fix behavior returned {:ok, [sub("would-flag-create")]} here. That's
      # the exact path that dropped recently-registered contracts from the
      # Capway snapshot and generated false :capway_create_contract action
      # items. Pin it to {:error, _}.
      results = [
        ok(1, [sub("would-flag-create")]),
        err(2, :anything)
      ]

      capture_log(fn ->
        assert {:error, {:partial_fetch, _}} =
                 CapwaySubscribers.merge_worker_results(results)
      end)
    end
  end

  describe "calculate_worker_ranges/3" do
    test "splits evenly when total divides cleanly" do
      assert CapwaySubscribers.calculate_worker_ranges(0, 300, 3) ==
               [{0, 100}, {100, 100}, {200, 100}]
    end

    test "distributes remainder across the first workers" do
      assert CapwaySubscribers.calculate_worker_ranges(0, 302, 3) ==
               [{0, 101}, {101, 101}, {202, 100}]
    end

    test "rejects empty ranges" do
      assert CapwaySubscribers.calculate_worker_ranges(0, 2, 3) ==
               [{0, 1}, {1, 1}]
    end

    test "starts at the given offset (the rows after the first page)" do
      # 6_137-row report: the first page took 0..99, workers share 100..6_136.
      assert CapwaySubscribers.calculate_worker_ranges(100, 6_037, 3) ==
               [{100, 2_013}, {2_113, 2_012}, {4_125, 2_012}]
    end

    test "yields no ranges when there is nothing left to fetch" do
      assert CapwaySubscribers.calculate_worker_ranges(100, 0, 3) == []
    end
  end

  describe "creditor/0" do
    setup do
      original = Application.get_env(:capway_sync, :capway_creditor)

      on_exit(fn ->
        Application.put_env(:capway_sync, :capway_creditor, original)
      end)

      :ok
    end

    test "returns the configured creditor id" do
      Application.put_env(:capway_sync, :capway_creditor, "999111")
      assert CapwaySubscribers.creditor() == "999111"
    end

    test "raises when the creditor is not configured" do
      Application.put_env(:capway_sync, :capway_creditor, nil)

      assert_raise RuntimeError, ~r/CAPWAY_CREDITOR is not configured/, fn ->
        CapwaySubscribers.creditor()
      end
    end

    test "raises when the creditor is blank" do
      Application.put_env(:capway_sync, :capway_creditor, "")

      assert_raise RuntimeError, ~r/CAPWAY_CREDITOR is not configured/, fn ->
        CapwaySubscribers.creditor()
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Page-level fetch logic (first page + counter, workers, validation, probe)
  # ---------------------------------------------------------------------------

  alias CapwaySync.Reactor.V1.Steps.CapwaySubscribers.Page

  defp subs(n, prefix, counter \\ 6_137),
    do: Enum.map(1..n//1, &sub("#{prefix}-#{&1}", counter))

  defp page(offset, requested, fetched),
    do: %Page{offset: offset, requested: requested, subscribers: subs(fetched, "o#{offset}")}

  # Builds a fetch fun backed by a fixed "report" of `total_rows` rows whose
  # rows all carry `counter` (defaults to the true total, like the real
  # report), and records every (offset, maxrows) call in the given agent.
  defp report_fetcher(total_rows, calls, counter \\ nil) do
    counter = counter || total_rows

    fn offset, maxrows ->
      Agent.update(calls, &[{offset, maxrows} | &1])
      available = max(total_rows - offset, 0)
      {:ok, subs(min(available, maxrows), "o#{offset}", counter)}
    end
  end

  # Same, with the label argument `fetch_pages/2` passes.
  defp labelled_report_fetcher(total_rows, calls, counter \\ nil) do
    fetch = report_fetcher(total_rows, calls, counter)
    fn offset, maxrows, _label -> fetch.(offset, maxrows) end
  end

  defp calls_in_order(calls), do: Agent.get(calls, &Enum.reverse/1)

  describe "Page helpers" do
    test "fetched/1 counts rows and short?/1 flags pages with fewer rows than requested" do
      assert Page.fetched(page(0, 100, 100)) == 100
      refute Page.short?(page(0, 100, 100))
      assert Page.short?(page(0, 100, 37))
      assert Page.short?(page(0, 100, 0))
    end
  end

  describe "fetch_worker_pages/4" do
    test "fetches a range in page-sized chunks and returns pages in offset order" do
      {:ok, calls} = Agent.start_link(fn -> [] end)
      fetch = report_fetcher(10_000, calls)

      assert {:ok, {1, pages}} = CapwaySubscribers.fetch_worker_pages(1, 200, 250, fetch)

      assert Enum.map(pages, &{&1.offset, &1.requested, Page.fetched(&1)}) == [
               {200, 100, 100},
               {300, 100, 100},
               {400, 50, 50}
             ]

      assert Agent.get(calls, &Enum.reverse/1) == [{200, 100}, {300, 100}, {400, 50}]
    end

    test "records an empty page instead of failing (validation decides later)" do
      fetch = fn
        100, _ -> {:ok, []}
        offset, maxrows -> {:ok, subs(maxrows, "o#{offset}")}
      end

      log =
        capture_log(fn ->
          assert {:ok, {2, pages}} = CapwaySubscribers.fetch_worker_pages(2, 0, 300, fetch)
          assert Enum.map(pages, &Page.fetched/1) == [100, 0, 100]
        end)

      assert log =~ "Got 0 subscribers from offset=100"
    end

    test "returns {:error, {worker_id, reason}} on the first page that fails" do
      fetch = fn
        100, _ -> {:error, {:fetch_error, :timeout}}
        offset, maxrows -> {:ok, subs(maxrows, "o#{offset}")}
      end

      assert {:error, {3, {:fetch_error, :timeout}}} =
               CapwaySubscribers.fetch_worker_pages(3, 0, 300, fetch)
    end

    test "stops at a short non-empty page instead of fetching the rest of the range" do
      {:ok, calls} = Agent.start_link(fn -> [] end)
      # Mirrors the 2026-09-08 run: worker 3 owned 11_965..17_947 but the
      # report ended at row 12_076.
      fetch = report_fetcher(12_076, calls)

      log =
        capture_log(fn ->
          assert {:ok, {3, pages}} = CapwaySubscribers.fetch_worker_pages(3, 11_965, 5_982, fetch)
          assert Enum.map(pages, &{&1.offset, Page.fetched(&1)}) == [{11_965, 100}, {12_065, 11}]
        end)

      assert Agent.get(calls, &Enum.reverse/1) == [{11_965, 100}, {12_065, 100}]
      assert log =~ "Worker 3: End of report reached at offset 12065"
    end

    test "stops after two consecutive empty pages" do
      {:ok, calls} = Agent.start_link(fn -> [] end)
      # Report ends exactly on a page boundary inside the range.
      fetch = report_fetcher(200, calls)

      assert {:ok, {2, pages}} = CapwaySubscribers.fetch_worker_pages(2, 0, 1_000, fetch)
      assert Enum.map(pages, &Page.fetched/1) == [100, 100, 0, 0]
      assert length(Agent.get(calls, & &1)) == 4
    end

    test "a range that starts past the end of the report costs two calls" do
      {:ok, calls} = Agent.start_link(fn -> [] end)
      fetch = report_fetcher(5_000, calls)

      assert {:ok, {3, pages}} = CapwaySubscribers.fetch_worker_pages(3, 11_965, 5_982, fetch)
      assert Enum.map(pages, &Page.fetched/1) == [0, 0]
      assert length(Agent.get(calls, & &1)) == 2
    end

    test "a zero-row range yields no pages and no fetches" do
      fetch = fn _, _ -> flunk("must not fetch") end
      assert {:ok, {1, []}} = CapwaySubscribers.fetch_worker_pages(1, 0, 0, fetch)
    end
  end

  describe "fetch_first_page/1" do
    test "returns the first page and the report total read from the counter" do
      {:ok, calls} = Agent.start_link(fn -> [] end)
      fetch = report_fetcher(6_137, calls)

      assert {:ok, %Page{offset: 0, requested: 100} = page, 6_137} =
               CapwaySubscribers.fetch_first_page(fetch)

      assert Page.fetched(page) == 100
      assert calls_in_order(calls) == [{0, 100}]
    end

    test "an empty first page is an empty report" do
      fetch = fn 0, 100 -> {:ok, []} end

      log =
        capture_log(fn ->
          assert {:ok, %Page{subscribers: []}, 0} = CapwaySubscribers.fetch_first_page(fetch)
        end)

      assert log =~ "returned no rows at all"
    end

    test "rejects a page whose rows carry no usable counter" do
      fetch = fn 0, 100 -> {:ok, [%CapwaySubscriber{raw_data: ["0", "not-a-number"]}]} end

      log =
        capture_log(fn ->
          assert {:error, {:invalid_report_total, {:invalid_counter, "not-a-number"}}} =
                   CapwaySubscribers.fetch_first_page(fetch)
        end)

      assert log =~ "Cannot read the report total"
    end

    test "rejects a page whose rows disagree on the counter" do
      fetch = fn 0, 100 -> {:ok, [sub("a", 10), sub("b", 11)]} end

      capture_log(fn ->
        assert {:error, {:invalid_report_total, {:inconsistent_counter, ["10", "11"]}}} =
                 CapwaySubscribers.fetch_first_page(fetch)
      end)
    end

    test "propagates a fetch error" do
      fetch = fn 0, 100 -> {:error, {:fetch_error, :timeout}} end

      assert {:error, {:first_page_error, {:fetch_error, :timeout}}} =
               CapwaySubscribers.fetch_first_page(fetch)
    end
  end

  describe "validate_row_count/2" do
    test "accepts pages whose rows add up to the expected total" do
      assert :ok = CapwaySubscribers.validate_row_count([page(0, 100, 100), page(100, 100, 37)], 137)
      assert :ok = CapwaySubscribers.validate_row_count([], 0)
    end

    test "rejects fewer rows than the counter (a page lost rows)" do
      pages = [page(0, 100, 100), page(100, 100, 0), page(200, 100, 100)]

      log =
        capture_log(fn ->
          assert {:error, {:row_count_mismatch, %{expected: 300, fetched: 200}}} =
                   CapwaySubscribers.validate_row_count(pages, 300)
        end)

      assert log =~ "counter says 300 rows but 200 were fetched"
    end

    test "rejects more rows than the counter" do
      capture_log(fn ->
        assert {:error, {:row_count_mismatch, %{expected: 50, fetched: 100}}} =
                 CapwaySubscribers.validate_row_count([page(0, 100, 100)], 50)
      end)
    end
  end

  describe "confirm_report_end/3" do
    test "is ok when the offset past the counter has no rows" do
      {:ok, calls} = Agent.start_link(fn -> [] end)
      fetch = report_fetcher(6_137, calls)

      assert :ok = CapwaySubscribers.confirm_report_end(6_137, 100, fetch)
      assert calls_in_order(calls) == [{6_137, 100}]
    end

    test "rejects a report that still has rows past its counter" do
      {:ok, calls} = Agent.start_link(fn -> [] end)
      # The counter claims 6_137 rows but the report really has 6_200.
      fetch = report_fetcher(6_200, calls, 6_137)

      log =
        capture_log(fn ->
          assert {:error,
                  {:rows_past_counter, %{counter: 6_137, probe_offset: 6_137, probe_fetched: 63}}} =
                   CapwaySubscribers.confirm_report_end(6_137, 100, fetch)
        end)

      assert log =~ "rows past its counter"
    end

    test "propagates a probe fetch error with its offset" do
      fetch = fn 6_137, _ -> {:error, {:fetch_error, :econnrefused}} end

      assert {:error, {:probe_error, 6_137, {:fetch_error, :econnrefused}}} =
               CapwaySubscribers.confirm_report_end(6_137, 100, fetch)
    end
  end

  describe "fetch_pages/2" do
    test "fetches the first page, splits the rest across workers and probes past the counter" do
      {:ok, calls} = Agent.start_link(fn -> [] end)
      fetch = labelled_report_fetcher(250, calls)

      log =
        capture_log(fn ->
          assert {:ok, pages, 250} = CapwaySubscribers.fetch_pages(nil, fetch)

          assert pages |> Enum.sort_by(& &1.offset) |> Enum.map(&{&1.offset, Page.fetched(&1)}) ==
                   [{0, 100}, {100, 50}, {150, 50}, {200, 50}]

          assert CapwaySubscribers.subscribers_from_pages(pages) |> length() == 250
        end)

      calls = calls_in_order(calls)
      assert hd(calls) == {0, 100}
      assert List.last(calls) == {250, 100}
      assert Enum.sort(calls) == [{0, 100}, {100, 50}, {150, 50}, {200, 50}, {250, 100}]
      assert log =~ "Capway report counter: 250 rows in total"
      assert log =~ "counter confirmed"
    end

    test "a report that fits in the first page needs no workers, only the probe" do
      {:ok, calls} = Agent.start_link(fn -> [] end)
      fetch = labelled_report_fetcher(37, calls)

      capture_log(fn ->
        assert {:ok, [%Page{offset: 0}], 37} = CapwaySubscribers.fetch_pages(nil, fetch)
      end)

      assert calls_in_order(calls) == [{0, 100}, {37, 100}]
    end

    test "an empty report costs exactly one call" do
      {:ok, calls} = Agent.start_link(fn -> [] end)
      fetch = labelled_report_fetcher(0, calls)

      capture_log(fn ->
        assert {:ok, [%Page{subscribers: []}], 0} = CapwaySubscribers.fetch_pages(nil, fetch)
      end)

      assert calls_in_order(calls) == [{0, 100}]
    end

    test "CAPWAY_MAX_PAGES caps the rows fetched and skips the probe" do
      {:ok, calls} = Agent.start_link(fn -> [] end)
      fetch = labelled_report_fetcher(6_137, calls)

      log =
        capture_log(fn ->
          assert {:ok, pages, 6_137} = CapwaySubscribers.fetch_pages(2, fetch)
          assert CapwaySubscribers.subscribers_from_pages(pages) |> length() == 200
        end)

      refute Enum.any?(calls_in_order(calls), fn {offset, _} -> offset >= 6_137 end)
      assert log =~ "Limiting Capway fetch to 2 pages"
      assert log =~ "skipping the end-of-report probe"
    end

    test "a page limit larger than the report still probes past the counter" do
      {:ok, calls} = Agent.start_link(fn -> [] end)
      fetch = labelled_report_fetcher(150, calls)

      capture_log(fn ->
        assert {:ok, _pages, 150} = CapwaySubscribers.fetch_pages(6, fetch)
      end)

      assert List.last(calls_in_order(calls)) == {150, 100}
    end

    test "fails when the report is shorter than its counter" do
      {:ok, calls} = Agent.start_link(fn -> [] end)
      # Counter says 300 rows but only 250 exist: worker pages come back short.
      fetch = labelled_report_fetcher(250, calls, 300)

      capture_log(fn ->
        assert {:error, {:row_count_mismatch, %{expected: 300, fetched: 250}}} =
                 CapwaySubscribers.fetch_pages(nil, fetch)
      end)
    end

    test "fails when a page in the middle silently comes back empty" do
      {:ok, calls} = Agent.start_link(fn -> [] end)
      real = labelled_report_fetcher(300, calls)

      fetch = fn
        100, maxrows, label -> real.(100, maxrows, label) |> then(fn _ -> {:ok, []} end)
        offset, maxrows, label -> real.(offset, maxrows, label)
      end

      capture_log(fn ->
        assert {:error, {:inconsistent_pages, %{short_offset: 100}}} =
                 CapwaySubscribers.fetch_pages(nil, fetch)
      end)
    end

    test "fails when the report has rows past its counter" do
      {:ok, calls} = Agent.start_link(fn -> [] end)
      fetch = labelled_report_fetcher(400, calls, 300)

      capture_log(fn ->
        assert {:error, {:rows_past_counter, %{counter: 300, probe_fetched: 100}}} =
                 CapwaySubscribers.fetch_pages(nil, fetch)
      end)
    end

    test "fails when a worker page fails after retries" do
      {:ok, calls} = Agent.start_link(fn -> [] end)
      real = labelled_report_fetcher(300, calls)

      # Worker 1 owns 100..166; its first page fails.
      fetch = fn
        100, _, _ -> {:error, {:fetch_error, :timeout}}
        offset, maxrows, label -> real.(offset, maxrows, label)
      end

      capture_log(fn ->
        assert {:error, {:partial_fetch, [{_worker, {:fetch_error, :timeout}}]}} =
                 CapwaySubscribers.fetch_pages(nil, fetch)
      end)
    end

    test "fails when the first page cannot be fetched" do
      fetch = fn 0, 100, "first" -> {:error, {:fetch_error, :nxdomain}} end

      assert {:error, {:first_page_error, {:fetch_error, :nxdomain}}} =
               CapwaySubscribers.fetch_pages(nil, fetch)
    end
  end

  describe "validate_page_sequence/1" do
    test "accepts an empty list and a fully populated sequence" do
      assert :ok = CapwaySubscribers.validate_page_sequence([])

      assert :ok =
               CapwaySubscribers.validate_page_sequence([page(0, 100, 100), page(100, 100, 100)])
    end

    test "accepts a short last page and an empty page after it" do
      pages = [page(0, 100, 100), page(100, 100, 42), page(200, 100, 0)]
      assert :ok = CapwaySubscribers.validate_page_sequence(pages)
    end

    test "is independent of the order pages are given in" do
      pages = [page(200, 100, 0), page(0, 100, 100), page(100, 100, 42)]
      assert :ok = CapwaySubscribers.validate_page_sequence(pages)
    end

    test "rejects an empty page that is followed by a page with rows" do
      pages = [page(0, 100, 100), page(100, 100, 0), page(200, 100, 100)]

      log =
        capture_log(fn ->
          assert {:error, {:inconsistent_pages, details}} =
                   CapwaySubscribers.validate_page_sequence(pages)

          assert details == %{
                   short_offset: 100,
                   short_requested: 100,
                   short_fetched: 0,
                   data_offset: 200,
                   data_fetched: 100
                 }
        end)

      assert log =~ "Inconsistent Capway page sequence"
    end

    test "rejects a short (non-empty) page that is followed by a page with rows" do
      pages = [page(0, 100, 60), page(100, 100, 100)]

      capture_log(fn ->
        assert {:error, {:inconsistent_pages, %{short_offset: 0, short_fetched: 60}}} =
                 CapwaySubscribers.validate_page_sequence(pages)
      end)
    end

    test "a short page in one worker's range followed by another worker's data is rejected" do
      # Worker 1 covered 0..199 and its second page silently came back empty;
      # worker 2 covered 200..399 normally.
      pages = [page(0, 100, 100), page(100, 100, 0), page(200, 100, 100), page(300, 100, 100)]

      capture_log(fn ->
        assert {:error, {:inconsistent_pages, %{short_offset: 100, data_offset: 200}}} =
                 CapwaySubscribers.validate_page_sequence(pages)
      end)
    end
  end

  describe "subscribers_from_pages/1" do
    test "flattens pages in offset order regardless of input order" do
      pages = [page(100, 100, 2), page(0, 100, 2)]

      assert CapwaySubscribers.subscribers_from_pages(pages) |> Enum.map(& &1.contract_ref_no) ==
               ["o0-1", "o0-2", "o100-1", "o100-2"]
    end
  end

  describe "merge_worker_results/1 with pages" do
    test "concatenates each worker's pages in worker order" do
      results = [
        ok(2, [page(200, 100, 100)]),
        ok(1, [page(0, 100, 100), page(100, 100, 100)])
      ]

      assert {:ok, pages} = CapwaySubscribers.merge_worker_results(results)
      assert Enum.map(pages, & &1.offset) == [0, 100, 200]
    end
  end

  describe "page_size/0" do
    test "is Capway's 100-row page cap" do
      assert CapwaySubscribers.page_size() == 100
    end
  end
end
