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
end
