defmodule CapwaySync.Models.Dynamodb.ActionItemTest do
  use ExUnit.Case, async: true

  alias CapwaySync.Models.Dynamodb.ActionItem

  describe "create_action_item/2" do
    test "defaults sub_action to nil when not provided in the data map" do
      item =
        ActionItem.create_action_item(:capway_create_contract, %{
          national_id: "196403273813",
          trinity_subscriber_id: 1,
          reason: "Missing in Capway"
        })

      assert item.action == :capway_create_contract
      assert item.sub_action == nil
      assert item.comment == "Missing in Capway"
    end

    test "stores the sub_action list when supplied" do
      item =
        ActionItem.create_action_item(:capway_update_customer, %{
          national_id: "196403273813",
          trinity_subscriber_id: 1,
          reason: "Email mismatch",
          sub_action: [:update_email]
        })

      assert item.action == :capway_update_customer
      assert item.sub_action == [:update_email]
    end

    test "supports multi-field sub_action lists" do
      both_item =
        ActionItem.create_action_item(:capway_update_customer, %{
          sub_action: [:update_nin, :update_email]
        })

      assert both_item.sub_action == [:update_nin, :update_email]

      all_item =
        ActionItem.create_action_item(:capway_update_customer, %{
          sub_action: [:update_nin, :update_email, :update_language]
        })

      assert all_item.sub_action == [:update_nin, :update_email, :update_language]
    end

    test "always populates id, created_at, timestamp, and pending status" do
      item = ActionItem.create_action_item(:capway_cancel_contract, %{})

      assert is_binary(item.id)
      assert item.status == :pending
      assert item.created_at == Date.utc_today() |> Date.to_string()
      assert is_integer(item.timestamp)
    end
  end
end
