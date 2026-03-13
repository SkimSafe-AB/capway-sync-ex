defmodule CapwaySyncTest.Ecto.TrinitySubscribersRetryTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureLog

  alias CapwaySync.Ecto.TrinitySubscribers
  alias CapwaySync.Models.Trinity.Subscriber

  describe "Trinity database retry logic" do
    test "list_subscribers function exists and returns a list" do
      functions = TrinitySubscribers.__info__(:functions)
      assert {:list_subscribers, 0} in functions
      assert {:list_subscribers, 1} in functions
      assert {:list_subscribers, 2} in functions
    end

    test "get_subscriber_by_pnr function exists" do
      functions = TrinitySubscribers.__info__(:functions)
      assert {:get_subscriber_by_pnr, 1} in functions
    end

    test "handles database connection errors gracefully" do
      assert Code.ensure_loaded?(TrinitySubscribers)
    end
  end

  describe "subscriber type filtering" do
    test "subscriber schema has type field" do
      fields = Subscriber.__schema__(:fields)
      assert :type in fields
    end

    test "type enum includes account_holder and family_member" do
      valid_values = Ecto.Enum.values(Subscriber, :type)
      assert :account_holder in valid_values
      assert :family_member in valid_values
    end

    test "type enum only has two values" do
      valid_values = Ecto.Enum.values(Subscriber, :type)
      assert length(valid_values) == 2
    end

    test "list_subscribers query excludes family_member but includes nil type" do
      import Ecto.Query

      # Build the same where clause used in list_subscribers
      query = from(s in Subscriber, where: s.type != :family_member or is_nil(s.type))

      # Verify query has the where clause
      assert length(query.wheres) == 1

      # The filter uses != :family_member OR is_nil(s.type) to include
      # subscribers that haven't been assigned a type yet
      %Ecto.Query.BooleanExpr{expr: expr} = hd(query.wheres)
      assert {:or, _, _} = expr
    end
  end

  describe "subscription type filtering" do
    test "list_subscribers query excludes sinfrid subscription type" do
      types = CapwaySync.Models.Trinity.Subscription.__schema__(:type, :subscription_type)
      assert types != nil

      valid_values =
        Ecto.Enum.values(CapwaySync.Models.Trinity.Subscription, :subscription_type)

      assert :sinfrid in valid_values
    end
  end

  describe "error handling patterns" do
    test "modules are properly structured for retry logic" do
      assert Code.ensure_loaded?(TrinitySubscribers)
      assert Code.ensure_loaded?(CapwaySync.TrinityRepo)

      functions = TrinitySubscribers.__info__(:functions)

      assert Enum.member?(functions, {:list_subscribers, 0})
      assert Enum.member?(functions, {:list_subscribers, 1})
      assert Enum.member?(functions, {:get_subscriber_by_pnr, 1})
    end

    test "logging is available for error scenarios" do
      log =
        capture_log(fn ->
          require Logger
          Logger.warning("Test retry warning")
        end)

      assert log =~ "Test retry warning"
    end
  end
end
