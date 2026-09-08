defmodule CapwaySync.Reactor.V1.Steps.CapwaySubscribersTest do
  @moduledoc """
  Unit tests for `CapwaySubscribers.merge_worker_results/1`.

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

  defp sub(contract_ref_no), do: %CapwaySubscriber{contract_ref_no: contract_ref_no}

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

  describe "calculate_worker_ranges/2" do
    test "splits evenly when total divides cleanly" do
      assert CapwaySubscribers.calculate_worker_ranges(300, 3) ==
               [{0, 100}, {100, 100}, {200, 100}]
    end

    test "distributes remainder across the first workers" do
      assert CapwaySubscribers.calculate_worker_ranges(302, 3) ==
               [{0, 101}, {101, 101}, {202, 100}]
    end

    test "rejects empty ranges" do
      assert CapwaySubscribers.calculate_worker_ranges(2, 3) ==
               [{0, 1}, {1, 1}]
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
  # Page-level fetch logic (tail sweep + page-sequence validation)
  # ---------------------------------------------------------------------------

  alias CapwaySync.Reactor.V1.Steps.CapwaySubscribers.Page

  defp subs(n, prefix \\ "ref"), do: Enum.map(1..n//1, &sub("#{prefix}-#{&1}"))

  defp page(offset, requested, fetched),
    do: %Page{offset: offset, requested: requested, subscribers: subs(fetched, "o#{offset}")}

  # Builds a fetch fun backed by a fixed "report" of `total_rows` rows, and
  # records every (offset, maxrows) call in the given agent.
  defp report_fetcher(total_rows, calls) do
    fn offset, maxrows ->
      Agent.update(calls, &[{offset, maxrows} | &1])
      available = max(total_rows - offset, 0)
      {:ok, subs(min(available, maxrows), "o#{offset}")}
    end
  end

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

    test "a zero-row range yields no pages and no fetches" do
      fetch = fn _, _ -> flunk("must not fetch") end
      assert {:ok, {1, []}} = CapwaySubscribers.fetch_worker_pages(1, 0, 0, fetch)
    end
  end

  describe "fetch_tail/3" do
    test "sweeps past the start offset until a short non-empty page" do
      {:ok, calls} = Agent.start_link(fn -> [] end)
      # 2,350 real rows but the REST customer count said 2,000
      fetch = report_fetcher(2_350, calls)

      assert {:ok, pages} = CapwaySubscribers.fetch_tail(2_000, 100, fetch)

      assert Enum.map(pages, &{&1.offset, Page.fetched(&1)}) == [
               {2_000, 100},
               {2_100, 100},
               {2_200, 100},
               {2_300, 50}
             ]

      # Stops right after the short page — no probe needed.
      assert Agent.get(calls, &Enum.reverse/1) == [
               {2_000, 100},
               {2_100, 100},
               {2_200, 100},
               {2_300, 100}
             ]
    end

    test "an empty first page is confirmed with exactly one probe" do
      {:ok, calls} = Agent.start_link(fn -> [] end)
      fetch = report_fetcher(2_000, calls)

      assert {:ok, [empty]} = CapwaySubscribers.fetch_tail(2_000, 100, fetch)
      assert Page.fetched(empty) == 0
      assert Agent.get(calls, &Enum.reverse/1) == [{2_000, 100}, {2_100, 100}]
    end

    test "a page that exactly fills the report ends with an empty page plus probe" do
      {:ok, calls} = Agent.start_link(fn -> [] end)
      fetch = report_fetcher(2_100, calls)

      assert {:ok, pages} = CapwaySubscribers.fetch_tail(2_000, 100, fetch)
      assert Enum.map(pages, &Page.fetched/1) == [100, 0]
      assert length(Agent.get(calls, & &1)) == 3
    end

    test "an empty page followed by data is an inconsistent sequence, not the end" do
      fetch = fn
        2_000, _ -> {:ok, []}
        2_100, _ -> {:ok, subs(40)}
      end

      assert {:error, {:inconsistent_pages, details}} =
               CapwaySubscribers.fetch_tail(2_000, 100, fetch)

      assert details.short_offset == 2_000
      assert details.data_offset == 2_100
      assert details.data_fetched == 40
    end

    test "propagates a fetch error with its offset" do
      fetch = fn
        2_000, _ -> {:ok, subs(100)}
        2_100, _ -> {:error, {:parse_error, :bad_xml}}
      end

      assert {:error, {:tail_fetch_error, 2_100, {:parse_error, :bad_xml}}} =
               CapwaySubscribers.fetch_tail(2_000, 100, fetch)
    end

    test "propagates a fetch error on the confirmation probe" do
      fetch = fn
        2_000, _ -> {:ok, []}
        2_100, _ -> {:error, {:fetch_error, :econnrefused}}
      end

      assert {:error, {:tail_fetch_error, 2_100, {:fetch_error, :econnrefused}}} =
               CapwaySubscribers.fetch_tail(2_000, 100, fetch)
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
