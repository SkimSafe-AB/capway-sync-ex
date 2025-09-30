defmodule CapwaySync.Reactor.V1.Steps.CompareDataTest do
  use ExUnit.Case
  alias CapwaySync.Reactor.V1.Steps.CompareData

  describe "run/3 - main Reactor step interface" do
    test "successfully compares subscribers and returns missing items" do
      trinity_subscribers = [
        %{id_number: "123", name: "Alice", status: "active"},
        %{id_number: "456", name: "Bob", status: "active"},
        %{id_number: "789", name: "Charlie", status: "active"}
      ]

      capway_subscribers = [
        %{id_number: "123", name: "Alice", active: true},
        %{id_number: "999", name: "David", active: true}
      ]

      arguments = %{
        trinity_subscribers: trinity_subscribers,
        capway_subscribers: capway_subscribers
      }

      assert {:ok, result} = CompareData.run(arguments, %{})

      # Alice (id: 123) is in both lists
      # Bob (id: 456) and Charlie (id: 789) are missing in Capway
      # David (customer_ref: 999) is missing in Trinity

      assert result.total_trinity == 3
      assert result.total_capway == 2
      assert result.missing_capway_count == 2
      assert result.missing_trinity_count == 1
      assert result.existing_in_both_count == 1

      assert Enum.any?(result.missing_in_capway, &(&1.id_number == "456"))
      assert Enum.any?(result.missing_in_capway, &(&1.id_number == "789"))
      assert Enum.any?(result.missing_in_trinity, &(&1.id_number == "999"))
      assert Enum.any?(result.existing_in_both, &(&1.id_number == "123"))
    end

    test "handles empty lists" do
      arguments = %{
        trinity_subscribers: [],
        capway_subscribers: []
      }

      assert {:ok, result} = CompareData.run(arguments, %{})

      assert result.total_trinity == 0
      assert result.total_capway == 0
      assert result.missing_capway_count == 0
      assert result.missing_trinity_count == 0
      assert result.existing_in_both_count == 0
      assert result.missing_in_capway == []
      assert result.missing_in_trinity == []
      assert result.existing_in_both == []
    end

    test "supports custom key configuration" do
      trinity_subscribers = [%{subscriber_id: "123", name: "Alice"}]
      capway_subscribers = [%{ref: "456", name: "Bob"}]

      arguments = %{
        trinity_subscribers: trinity_subscribers,
        capway_subscribers: capway_subscribers
      }

      options = [trinity_key: :subscriber_id, capway_key: :ref]

      assert {:ok, result} = CompareData.run(arguments, %{}, options)

      assert result.missing_capway_count == 1
      assert result.missing_trinity_count == 1
      assert result.existing_in_both_count == 0
    end

    test "returns error for missing arguments" do
      arguments = %{trinity_subscribers: []}

      assert {:error, "Missing required argument: capway_subscribers"} =
        CompareData.run(arguments, %{})
    end

    test "returns error for non-list arguments" do
      arguments = %{
        trinity_subscribers: %{not_a_list: true},
        capway_subscribers: []
      }

      assert {:error, "Argument trinity_subscribers must be a list"} =
        CompareData.run(arguments, %{})
    end

    test "correctly identifies existing_in_both accounts" do
      trinity_subscribers = [
        %{id_number: "100", name: "Alice"},
        %{id_number: "200", name: "Bob"},
        %{id_number: "300", name: "Charlie"}
      ]

      capway_subscribers = [
        %{id_number: "100", name: "Alice", collection: "1"},
        %{id_number: "200", name: "Bob", collection: "3"},
        %{id_number: "400", name: "David", collection: "0"}
      ]

      arguments = %{
        trinity_subscribers: trinity_subscribers,
        capway_subscribers: capway_subscribers
      }

      assert {:ok, result} = CompareData.run(arguments, %{})

      # Alice (100) and Bob (200) exist in both
      # Charlie (300) missing in Capway
      # David (400) missing in Trinity
      assert result.existing_in_both_count == 2
      assert result.missing_capway_count == 1
      assert result.missing_trinity_count == 1

      existing_refs = Enum.map(result.existing_in_both, & &1.id_number)
      assert "100" in existing_refs
      assert "200" in existing_refs
      refute "400" in existing_refs

      # Verify these are Capway records (have collection field)
      assert Enum.all?(result.existing_in_both, &Map.has_key?(&1, :collection))
    end
  end

  describe "find_missing_items/4" do
    test "identifies missing items correctly with different keys" do
      trinity_list = [
        %{id: "100", name: "John"},
        %{id: "200", name: "Jane"},
        %{id: "300", name: "Jack"}
      ]

      capway_list = [
        %{customer_ref: "100", name: "John"},
        %{customer_ref: "400", name: "Jill"}
      ]

      result = CompareData.find_missing_items(trinity_list, capway_list, :id, :customer_ref)

      assert result.total_trinity == 3
      assert result.total_capway == 2
      assert result.missing_capway_count == 2
      assert result.missing_trinity_count == 1

      # Jane and Jack should be missing in Capway
      missing_in_capway_ids = Enum.map(result.missing_in_capway, & &1.id)
      assert "200" in missing_in_capway_ids
      assert "300" in missing_in_capway_ids

      # Jill should be missing in Trinity
      missing_in_trinity_refs = Enum.map(result.missing_in_trinity, & &1.customer_ref)
      assert "400" in missing_in_trinity_refs
    end

    test "handles identical lists" do
      list = [%{id: "123", name: "Same"}]

      result = CompareData.find_missing_items(list, list, :id, :id)

      assert result.missing_capway_count == 0
      assert result.missing_trinity_count == 0
      assert result.missing_in_capway == []
      assert result.missing_in_trinity == []
    end

    test "handles lists with nil key values" do
      trinity_list = [
        %{id: "100", name: "Valid"},
        %{id: nil, name: "Invalid1"},
        %{name: "Invalid2"}  # missing key
      ]

      capway_list = [
        %{customer_ref: "200", name: "Different"},
        %{customer_ref: nil, name: "Invalid3"}
      ]

      result = CompareData.find_missing_items(trinity_list, capway_list, :id, :customer_ref)

      # Only valid entries should be considered
      assert result.missing_capway_count == 1  # "100" missing in capway
      assert result.missing_trinity_count == 1  # "200" missing in trinity
    end
  end

  describe "extract_key_values/2" do
    test "extracts key values from list of maps" do
      items = [
        %{id: 1, name: "First"},
        %{id: 2, name: "Second"},
        %{id: 3, name: "Third"}
      ]

      assert CompareData.extract_key_values(items, :id) == [1, 2, 3]
      assert CompareData.extract_key_values(items, :name) == ["First", "Second", "Third"]
    end

    test "handles missing keys gracefully" do
      items = [
        %{id: 1, name: "First"},
        %{name: "Second"},  # missing :id key
        %{id: 3, other: "Third"}
      ]

      result = CompareData.extract_key_values(items, :id)
      assert result == [1, 3]  # nil values are filtered out
    end

    test "handles nil values" do
      items = [
        %{id: 1},
        %{id: nil},
        %{id: 2}
      ]

      result = CompareData.extract_key_values(items, :id)
      assert result == [1, 2]  # nil values are filtered out
    end

    test "handles empty list" do
      assert CompareData.extract_key_values([], :any_key) == []
    end
  end

  describe "find_items_by_keys/3" do
    test "finds items matching keys in set" do
      items = [
        %{id: "a", value: 1},
        %{id: "b", value: 2},
        %{id: "c", value: 3}
      ]

      keys_set = MapSet.new(["a", "c"])

      result = CompareData.find_items_by_keys(items, keys_set, :id)

      assert length(result) == 2
      assert Enum.any?(result, &(&1.id == "a"))
      assert Enum.any?(result, &(&1.id == "c"))
      refute Enum.any?(result, &(&1.id == "b"))
    end

    test "handles empty keys set" do
      items = [%{id: "a", value: 1}]
      keys_set = MapSet.new([])

      result = CompareData.find_items_by_keys(items, keys_set, :id)
      assert result == []
    end

    test "handles items with nil key values" do
      items = [
        %{id: "a", value: 1},
        %{id: nil, value: 2},
        %{value: 3}  # missing key
      ]

      keys_set = MapSet.new(["a", nil])

      result = CompareData.find_items_by_keys(items, keys_set, :id)
      assert length(result) == 1
      assert hd(result).id == "a"
    end
  end

  describe "compare_with_keys/1 - legacy compatibility" do
    test "returns true when lists have identical values in same order" do
      capway_list = [%{id: 1}, %{id: 2}, %{id: 3}]
      trinity_list = [%{subscriber_id: 1}, %{subscriber_id: 2}, %{subscriber_id: 3}]

      params = %{
        capway_list: capway_list,
        trinity_list: trinity_list,
        capway_key: :id,
        trinity_key: :subscriber_id
      }

      assert CompareData.compare_with_keys(params) == true
    end

    test "returns false when lists have different values" do
      capway_list = [%{id: 1}, %{id: 2}, %{id: 3}]
      trinity_list = [%{subscriber_id: 1}, %{subscriber_id: 2}, %{subscriber_id: 4}]

      params = %{
        capway_list: capway_list,
        trinity_list: trinity_list,
        capway_key: :id,
        trinity_key: :subscriber_id
      }

      assert CompareData.compare_with_keys(params) == false
    end

    test "returns false when lists have same values but different order" do
      capway_list = [%{id: 1}, %{id: 2}, %{id: 3}]
      trinity_list = [%{subscriber_id: 3}, %{subscriber_id: 1}, %{subscriber_id: 2}]

      params = %{
        capway_list: capway_list,
        trinity_list: trinity_list,
        capway_key: :id,
        trinity_key: :subscriber_key
      }

      assert CompareData.compare_with_keys(params) == false
    end

    test "returns false when capway list is longer" do
      capway_list = [%{id: 1}, %{id: 2}, %{id: 3}]
      trinity_list = [%{subscriber_id: 1}, %{subscriber_id: 2}]

      params = %{
        capway_list: capway_list,
        trinity_list: trinity_list,
        capway_key: :id,
        trinity_key: :subscriber_id
      }

      assert CompareData.compare_with_keys(params) == false
    end

    test "returns false when trinity list is longer" do
      capway_list = [%{id: 1}, %{id: 2}]
      trinity_list = [%{subscriber_id: 1}, %{subscriber_id: 2}, %{subscriber_id: 3}]

      params = %{
        capway_list: capway_list,
        trinity_list: trinity_list,
        capway_key: :id,
        trinity_key: :subscriber_id
      }

      assert CompareData.compare_with_keys(params) == false
    end

    test "returns true when both lists are empty" do
      capway_list = []
      trinity_list = []

      params = %{
        capway_list: capway_list,
        trinity_list: trinity_list,
        capway_key: :id,
        trinity_key: :subscriber_id
      }

      assert CompareData.compare_with_keys(params) == true
    end

    test "handles nil values in keys" do
      capway_list = [%{id: nil}, %{id: 2}, %{id: 3}]
      trinity_list = [%{subscriber_id: nil}, %{subscriber_id: 2}, %{subscriber_id: 3}]

      params = %{
        capway_list: capway_list,
        trinity_list: trinity_list,
        capway_key: :id,
        trinity_key: :subscriber_id
      }

      assert CompareData.compare_with_keys(params) == true
    end

    test "handles missing keys (returns nil values)" do
      capway_list = [%{other_key: 1}, %{id: 2}]
      trinity_list = [%{subscriber_id: nil}, %{subscriber_id: 2}]

      params = %{
        capway_list: capway_list,
        trinity_list: trinity_list,
        capway_key: :id,
        trinity_key: :subscriber_id
      }

      assert CompareData.compare_with_keys(params) == true
    end

    test "handles different data types" do
      capway_list = [%{id: "1"}, %{id: "2"}, %{id: "3"}]
      trinity_list = [%{subscriber_id: 1}, %{subscriber_id: 2}, %{subscriber_id: 3}]

      params = %{
        capway_list: capway_list,
        trinity_list: trinity_list,
        capway_key: :id,
        trinity_key: :subscriber_id
      }

      assert CompareData.compare_with_keys(params) == false
    end

    test "works with string keys" do
      capway_list = [%{"id" => 1}, %{"id" => 2}, %{"id" => 3}]
      trinity_list = [%{"subscriber_id" => 1}, %{"subscriber_id" => 2}, %{"subscriber_id" => 3}]

      params = %{
        capway_list: capway_list,
        trinity_list: trinity_list,
        capway_key: "id",
        trinity_key: "subscriber_id"
      }

      assert CompareData.compare_with_keys(params) == true
    end

    test "works with complex nested structures" do
      capway_list = [
        %{user: %{id: 1, name: "Alice"}},
        %{user: %{id: 2, name: "Bob"}}
      ]
      trinity_list = [
        %{subscriber: %{id: 1, name: "Alice"}},
        %{subscriber: %{id: 2, name: "Bob"}}
      ]

      params = %{
        capway_list: capway_list,
        trinity_list: trinity_list,
        capway_key: :user,
        trinity_key: :subscriber
      }

      assert CompareData.compare_with_keys(params) == true
    end

    test "works with real subscriber data structure" do
      capway_list = [
        %{customer_ref: "49866", name: "Riccardo Robotti", id_number: "194902289471"},
        %{customer_ref: "46881", name: "Anna Helena Hansson", id_number: "193812207169"}
      ]
      trinity_list = [
        %{id: "49866", full_name: "Riccardo Robotti", personal_id: "194902289471"},
        %{id: "46881", full_name: "Anna Helena Hansson", personal_id: "193812207169"}
      ]

      params = %{
        capway_list: capway_list,
        trinity_list: trinity_list,
        capway_key: :customer_ref,
        trinity_key: :id
      }

      assert CompareData.compare_with_keys(params) == true
    end

    test "returns false with real subscriber data when IDs don't match" do
      capway_list = [
        %{customer_ref: "49866", name: "Riccardo Robotti"},
        %{customer_ref: "46881", name: "Anna Helena Hansson"}
      ]
      trinity_list = [
        %{id: "49866", full_name: "Riccardo Robotti"},
        %{id: "46999", full_name: "Anna Helena Hansson"}  # Different ID
      ]

      params = %{
        capway_list: capway_list,
        trinity_list: trinity_list,
        capway_key: :customer_ref,
        trinity_key: :id
      }

      assert CompareData.compare_with_keys(params) == false
    end

    test "handles large lists efficiently" do
      large_capway_list = Enum.map(1..1000, fn i -> %{id: i} end)
      large_trinity_list = Enum.map(1..1000, fn i -> %{subscriber_id: i} end)

      params = %{
        capway_list: large_capway_list,
        trinity_list: large_trinity_list,
        capway_key: :id,
        trinity_key: :subscriber_id
      }

      assert CompareData.compare_with_keys(params) == true
    end
  end
end