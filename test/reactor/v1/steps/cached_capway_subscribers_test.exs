defmodule CapwaySync.Reactor.V1.Steps.CachedCapwaySubscribersTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureLog

  alias CapwaySync.Reactor.V1.Steps.CachedCapwaySubscribers

  setup_all do
    Code.ensure_loaded!(CachedCapwaySubscribers)
    :ok
  end

  describe "module" do
    test "compiles successfully" do
      assert Code.ensure_loaded?(CachedCapwaySubscribers)
    end

    test "implements Reactor.Step behaviour" do
      behaviours =
        CachedCapwaySubscribers.__info__(:attributes)
        |> Keyword.get_values(:behaviour)
        |> List.flatten()

      assert Reactor.Step in behaviours
    end
  end

  describe "run/3" do
    test "function exists with arity 3" do
      assert function_exported?(CachedCapwaySubscribers, :run, 3)
    end
  end

  describe "compensate/4" do
    test "function exists with arity 4" do
      assert function_exported?(CachedCapwaySubscribers, :compensate, 4)
    end
  end

  describe "undo/4" do
    test "function exists with arity 4" do
      assert function_exported?(CachedCapwaySubscribers, :undo, 4)
    end
  end

  # ---------------------------------------------------------------------------
  # Snapshot-shrink guard
  # ---------------------------------------------------------------------------

  defp with_tolerance(tolerance, fun) do
    previous = Application.get_env(:capway_sync, :capway_snapshot_drop_tolerance)
    Application.put_env(:capway_sync, :capway_snapshot_drop_tolerance, tolerance)

    try do
      fun.()
    after
      Application.put_env(:capway_sync, :capway_snapshot_drop_tolerance, previous)
    end
  end

  defp rows(n), do: List.duplicate(%CapwaySync.Models.CapwaySubscriber{}, n)

  describe "drop_tolerance/0" do
    test "reads the configured fraction" do
      with_tolerance(0.2, fn -> assert CachedCapwaySubscribers.drop_tolerance() == 0.2 end)
    end

    test "falls back to 5% when unset or invalid" do
      with_tolerance(nil, fn -> assert CachedCapwaySubscribers.drop_tolerance() == 0.05 end)
      with_tolerance("junk", fn -> assert CachedCapwaySubscribers.drop_tolerance() == 0.05 end)
      with_tolerance(-1, fn -> assert CachedCapwaySubscribers.drop_tolerance() == 0.05 end)
    end
  end

  describe "snapshot_shrunk?/3" do
    test "true only when the drop exceeds the tolerance" do
      assert CachedCapwaySubscribers.snapshot_shrunk?(940, 1000, 0.05)
      refute CachedCapwaySubscribers.snapshot_shrunk?(950, 1000, 0.05)
      refute CachedCapwaySubscribers.snapshot_shrunk?(1000, 1000, 0.05)
      refute CachedCapwaySubscribers.snapshot_shrunk?(1200, 1000, 0.05)
    end

    test "a tolerance of 1.0 disables the check" do
      refute CachedCapwaySubscribers.snapshot_shrunk?(0, 1000, 1.0)
    end

    test "never shrunk without a meaningful previous count" do
      refute CachedCapwaySubscribers.snapshot_shrunk?(0, 0, 0.05)
      refute CachedCapwaySubscribers.snapshot_shrunk?(0, nil, 0.05)
    end
  end

  describe "guard_against_shrunken_snapshot/3" do
    test "passes when no previous manifest exists" do
      lookup = fn _date -> {:miss} end

      assert :ok =
               CachedCapwaySubscribers.guard_against_shrunken_snapshot(
                 rows(10),
                 "2026-09-02",
                 lookup
               )
    end

    test "passes when a lookup errors" do
      lookup = fn _date -> {:error, :boom} end

      assert :ok =
               CachedCapwaySubscribers.guard_against_shrunken_snapshot(
                 rows(10),
                 "2026-09-02",
                 lookup
               )
    end

    test "compares against yesterday's manifest first" do
      lookup = fn
        "2026-09-01" -> {:ok, %{total_subscribers: 1000}}
        "2026-08-31" -> {:ok, %{total_subscribers: 5000}}
      end

      with_tolerance(0.05, fn ->
        assert :ok =
                 CachedCapwaySubscribers.guard_against_shrunken_snapshot(
                   rows(980),
                   "2026-09-02",
                   lookup
                 )
      end)
    end

    test "falls back to the day before yesterday when yesterday is missing" do
      {:ok, seen} = Agent.start_link(fn -> [] end)

      lookup = fn date ->
        Agent.update(seen, &[date | &1])

        case date do
          "2026-09-01" -> {:miss}
          "2026-08-31" -> {:ok, %{total_subscribers: 1000}}
        end
      end

      with_tolerance(0.05, fn ->
        log =
          capture_log(fn ->
            assert {:error, {:snapshot_shrunk, details}} =
                     CachedCapwaySubscribers.guard_against_shrunken_snapshot(
                       rows(500),
                       "2026-09-02",
                       lookup
                     )

            assert details == %{
                     current: 500,
                     previous: 1000,
                     previous_date: "2026-08-31",
                     tolerance: 0.05
                   }
          end)

        assert log =~ "Capway snapshot shrunk"
      end)

      assert Agent.get(seen, &Enum.reverse/1) == ["2026-09-01", "2026-08-31"]
    end

    test "rejects a snapshot that dropped more than the tolerance" do
      lookup = fn _ -> {:ok, %{total_subscribers: 2000}} end

      with_tolerance(0.05, fn ->
        capture_log(fn ->
          assert {:error, {:snapshot_shrunk, %{current: 1899, previous: 2000}}} =
                   CachedCapwaySubscribers.guard_against_shrunken_snapshot(
                     rows(1899),
                     "2026-09-02",
                     lookup
                   )
        end)
      end)
    end

    test "accepts a snapshot within tolerance or larger" do
      lookup = fn _ -> {:ok, %{total_subscribers: 2000}} end

      with_tolerance(0.05, fn ->
        assert :ok =
                 CachedCapwaySubscribers.guard_against_shrunken_snapshot(
                   rows(1900),
                   "2026-09-02",
                   lookup
                 )

        assert :ok =
                 CachedCapwaySubscribers.guard_against_shrunken_snapshot(
                   rows(2100),
                   "2026-09-02",
                   lookup
                 )
      end)
    end

    test "ignores a previous manifest with a zero count" do
      lookup = fn _ -> {:ok, %{total_subscribers: 0}} end

      assert :ok =
               CachedCapwaySubscribers.guard_against_shrunken_snapshot(
                 rows(0),
                 "2026-09-02",
                 lookup
               )
    end
  end
end
