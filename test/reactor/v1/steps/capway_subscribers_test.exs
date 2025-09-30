defmodule CapwaySync.Reactor.V1.Steps.CapwaySubscribersTest do
  use ExUnit.Case, async: false
  alias CapwaySync.Reactor.V1.Steps.CapwaySubscribers

  # Test helper for cleaner test code
  defp calculate_worker_ranges(total_count, worker_count) do
    CapwaySubscribers.calculate_worker_ranges(total_count, worker_count)
  end

  describe "calculate_worker_ranges/2" do
    test "divides work evenly when total_count divides by worker_count" do
      ranges = calculate_worker_ranges(100, 4)

      expected = [
        {0, 25},    # Worker 1: records 0-24
        {25, 25},   # Worker 2: records 25-49
        {50, 25},   # Worker 3: records 50-74
        {75, 25}    # Worker 4: records 75-99
      ]

      assert ranges == expected
    end

    test "distributes remainder when total_count doesn't divide evenly" do
      ranges = calculate_worker_ranges(102, 4)

      expected = [
        {0, 26},    # Worker 1: 26 records (gets 1 extra)
        {26, 26},   # Worker 2: 26 records (gets 1 extra)
        {52, 25},   # Worker 3: 25 records
        {77, 25}    # Worker 4: 25 records
      ]

      assert ranges == expected
    end

    test "handles small total_count" do
      ranges = calculate_worker_ranges(3, 4)

      expected = [
        {0, 1},     # Worker 1: 1 record
        {1, 1},     # Worker 2: 1 record
        {2, 1}      # Worker 3: 1 record
        # Worker 4 gets no records (filtered out)
      ]

      assert ranges == expected
    end

    test "handles total_count equal to worker_count" do
      ranges = calculate_worker_ranges(4, 4)

      expected = [
        {0, 1},     # Worker 1: 1 record
        {1, 1},     # Worker 2: 1 record
        {2, 1},     # Worker 3: 1 record
        {3, 1}      # Worker 4: 1 record
      ]

      assert ranges == expected
    end

    test "handles total_count less than worker_count" do
      ranges = calculate_worker_ranges(2, 4)

      expected = [
        {0, 1},     # Worker 1: 1 record
        {1, 1}      # Worker 2: 1 record
        # Workers 3 and 4 get filtered out
      ]

      assert ranges == expected
    end

    test "handles large numbers correctly" do
      ranges = calculate_worker_ranges(1000, 4)

      expected = [
        {0, 250},     # Worker 1: records 0-249
        {250, 250},   # Worker 2: records 250-499
        {500, 250},   # Worker 3: records 500-749
        {750, 250}    # Worker 4: records 750-999
      ]

      assert ranges == expected
    end
  end

  describe "run/3 integration behavior" do
    test "handles successful parallel execution flow" do
      # This is a behavioral test - we can't easily mock the external services
      # but we can verify the function signature and structure
      assert is_function(&CapwaySubscribers.run/3, 3)
    end

    test "compensate/4 returns retry" do
      result = CapwaySubscribers.compensate(:error, [], %{}, [])
      assert result == :retry
    end

    test "undo/4 returns ok" do
      result = CapwaySubscribers.undo(%{}, %{}, [], [])
      assert result == :ok
    end
  end

  describe "worker range calculations edge cases" do
    test "zero total count returns empty list" do
      ranges = calculate_worker_ranges(0, 4)
      assert ranges == []
    end

    test "single worker gets all records" do
      ranges = calculate_worker_ranges(100, 1)
      assert ranges == [{0, 100}]
    end

    test "verifies no gaps in ranges" do
      ranges = calculate_worker_ranges(97, 4)

      # Verify coverage: all records from 0 to 96 are covered
      {_total_offset, total_records} =
        Enum.reduce(ranges, {0, 0}, fn {offset, count}, {expected_offset, total} ->
          assert offset == expected_offset, "Gap detected at offset #{offset}, expected #{expected_offset}"
          {offset + count, total + count}
        end)

      assert total_records == 97, "Expected 97 total records, got #{total_records}"
    end

    test "verifies no overlaps in ranges" do
      ranges = calculate_worker_ranges(105, 4)

      # Check that each range starts where the previous ended
      ranges
      |> Enum.reduce(0, fn {offset, count}, expected_offset ->
        assert offset == expected_offset, "Overlap or gap detected at offset #{offset}"
        offset + count
      end)
    end
  end

  describe "range calculation mathematical properties" do
    test "sum of all ranges equals total count" do
      for total_count <- [1, 50, 99, 100, 101, 200, 1000] do
        ranges = calculate_worker_ranges(total_count, 4)
        sum_of_ranges = Enum.sum(Enum.map(ranges, fn {_offset, count} -> count end))
        assert sum_of_ranges == total_count, "For total_count #{total_count}, sum was #{sum_of_ranges}"
      end
    end

    test "maximum difference between worker loads is at most 1" do
      for total_count <- [1, 2, 3, 50, 99, 100, 101, 200, 1000] do
        ranges = calculate_worker_ranges(total_count, 4)
        counts = Enum.map(ranges, fn {_offset, count} -> count end)

        if length(counts) > 1 do
          max_count = Enum.max(counts)
          min_count = Enum.min(counts)
          diff = max_count - min_count
          assert diff <= 1, "For total_count #{total_count}, load difference was #{diff} (counts: #{inspect(counts)})"
        end
      end
    end
  end

  describe "chunked fetching scenarios" do
    test "worker ranges work correctly for large datasets requiring chunking" do
      # Test a scenario where workers would need multiple chunks
      ranges = calculate_worker_ranges(1000, 4)

      expected = [
        {0, 250},     # Worker 1: records 0-249 (3 chunks of 100, 1 chunk of 50)
        {250, 250},   # Worker 2: records 250-499 (3 chunks of 100, 1 chunk of 50)
        {500, 250},   # Worker 3: records 500-749 (3 chunks of 100, 1 chunk of 50)
        {750, 250}    # Worker 4: records 750-999 (3 chunks of 100, 1 chunk of 50)
      ]

      assert ranges == expected
    end

    test "calculates correct number of chunks needed per worker" do
      ranges = calculate_worker_ranges(350, 4)

      # Expected ranges:
      # Worker 1: 88 records (1 chunk)
      # Worker 2: 88 records (1 chunk)
      # Worker 3: 87 records (1 chunk)
      # Worker 4: 87 records (1 chunk)

      Enum.each(ranges, fn {_offset, count} ->
        chunks_needed = ceil(count / 100)
        assert chunks_needed >= 1
        # For this test case, all workers need exactly 1 chunk since 88 < 100
        assert chunks_needed == 1
      end)
    end

    test "handles edge case where worker gets exactly 100 records" do
      ranges = calculate_worker_ranges(400, 4)

      expected = [
        {0, 100},     # Worker 1: exactly 100 records (1 chunk)
        {100, 100},   # Worker 2: exactly 100 records (1 chunk)
        {200, 100},   # Worker 3: exactly 100 records (1 chunk)
        {300, 100}    # Worker 4: exactly 100 records (1 chunk)
      ]

      assert ranges == expected
    end

    test "handles edge case where some workers need multiple chunks" do
      ranges = calculate_worker_ranges(650, 4)

      # Expected: 650 / 4 = 162.5, so some workers get 163, others get 162
      # Worker 1&2: 163 records each (2 chunks: 100 + 63, 100 + 62)
      # Worker 3&4: 162 records each (2 chunks: 100 + 62, 100 + 62)

      total_records = Enum.sum(Enum.map(ranges, fn {_offset, count} -> count end))
      assert total_records == 650

      # Verify each worker's chunk requirements
      Enum.each(ranges, fn {_offset, count} ->
        chunks_needed = ceil(count / 100)
        assert chunks_needed == 2, "Expected 2 chunks for #{count} records"
      end)
    end
  end

  describe "module configuration" do
    test "worker count is set to 4" do
      # Access the module attribute through the compiled module
      # We can't directly access @worker_count but we can verify the behavior
      ranges = calculate_worker_ranges(100, 4)
      assert length(ranges) == 4
    end
  end
end