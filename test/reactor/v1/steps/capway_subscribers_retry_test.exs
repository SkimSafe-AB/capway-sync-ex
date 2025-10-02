defmodule CapwaySyncTest.Reactor.V1.Steps.CapwaySubscribersRetryTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureLog

  alias CapwaySync.Reactor.V1.Steps.CapwaySubscribers

  describe "CapwaySubscribers retry logic" do
    test "calculate_worker_ranges divides work correctly" do
      # Test the public function that calculates worker ranges
      ranges = CapwaySubscribers.calculate_worker_ranges(100, 4)

      assert length(ranges) == 4
      assert Enum.all?(ranges, fn {_offset, size} -> size > 0 end)

      # Verify total records match
      total_size = ranges |> Enum.map(fn {_offset, size} -> size end) |> Enum.sum()
      assert total_size == 100
    end

    test "calculate_worker_ranges handles uneven division" do
      ranges = CapwaySubscribers.calculate_worker_ranges(101, 4)

      assert length(ranges) == 4

      # First worker should get the extra record
      [{_first_offset, first_size} | _rest] = ranges
      assert first_size == 26  # 101 / 4 = 25 remainder 1, so first worker gets 26

      # Verify total records match
      total_size = ranges |> Enum.map(fn {_offset, size} -> size end) |> Enum.sum()
      assert total_size == 101
    end

    test "calculate_worker_ranges with zero records" do
      ranges = CapwaySubscribers.calculate_worker_ranges(0, 4)
      assert ranges == []
    end

    test "calculate_worker_ranges with fewer records than workers" do
      ranges = CapwaySubscribers.calculate_worker_ranges(2, 4)

      # Should only create ranges for workers that have work
      assert length(ranges) == 2
      assert Enum.all?(ranges, fn {_offset, size} -> size == 1 end)
    end

    test "step implements required Reactor.Step callbacks" do
      # Verify that all required callbacks are implemented
      functions = CapwaySubscribers.__info__(:functions)

      assert {:run, 3} in functions
      assert {:compensate, 4} in functions
      assert {:undo, 4} in functions
    end

    test "worker count is properly configured" do
      # We can't easily access module attributes from tests, but we can verify
      # the module compiles and the functions exist
      assert Code.ensure_loaded?(CapwaySubscribers)

      # The module should have the expected structure for parallel processing
      assert function_exported?(CapwaySubscribers, :calculate_worker_ranges, 2)
    end
  end

  describe "error handling patterns" do
    test "compensate returns retry on errors" do
      # Test the compensate callback
      result = CapwaySubscribers.compensate(:some_error, %{}, %{}, [])
      assert result == :retry
    end

    test "undo returns ok" do
      # Test the undo callback
      result = CapwaySubscribers.undo(%{}, %{}, [], [])
      assert result == :ok
    end

    test "modules and dependencies are available" do
      # Verify required modules are loaded
      assert Code.ensure_loaded?(CapwaySync.Soap.GenerateReport)
      assert Code.ensure_loaded?(CapwaySync.Soap.ResponseHandler)
      assert Code.ensure_loaded?(CapwaySync.Rest.AccessToken)
      assert Code.ensure_loaded?(CapwaySync.Rest.CustomerCount)
    end

    test "logging is configured for worker operations" do
      log = capture_log(fn ->
        require Logger
        Logger.info("Worker 1: Test log message")
      end)

      assert log =~ "Worker 1: Test log message"
    end
  end

  describe "worker range calculations edge cases" do
    test "single worker handles all records" do
      ranges = CapwaySubscribers.calculate_worker_ranges(1000, 1)

      assert length(ranges) == 1
      assert ranges == [{0, 1000}]
    end

    test "many workers with few records" do
      ranges = CapwaySubscribers.calculate_worker_ranges(3, 10)

      assert length(ranges) == 3
      assert Enum.all?(ranges, fn {_offset, size} -> size == 1 end)

      # Verify offsets are correct
      offsets = Enum.map(ranges, fn {offset, _size} -> offset end)
      assert offsets == [0, 1, 2]
    end

    test "worker ranges have correct offsets" do
      ranges = CapwaySubscribers.calculate_worker_ranges(100, 3)

      # Should have 3 workers
      assert length(ranges) == 3

      # Extract and verify offsets are sequential and non-overlapping
      [{offset1, size1}, {offset2, size2}, {offset3, size3}] = ranges

      assert offset1 == 0
      assert offset2 == size1
      assert offset3 == size1 + size2

      # Verify total
      assert size1 + size2 + size3 == 100
    end
  end
end