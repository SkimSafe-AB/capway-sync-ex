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

    test "stores sub_action atom when supplied" do
      item =
        ActionItem.create_action_item(:capway_update_customer, %{
          national_id: "196403273813",
          trinity_subscriber_id: 1,
          reason: "Email mismatch",
          sub_action: :update_email
        })

      assert item.action == :capway_update_customer
      assert item.sub_action == :update_email
    end

    test "supports the :update_nin and :update_email_and_nin sub_actions" do
      nin_item =
        ActionItem.create_action_item(:capway_update_customer, %{sub_action: :update_nin})

      assert nin_item.sub_action == :update_nin

      both_item =
        ActionItem.create_action_item(:capway_update_customer, %{
          sub_action: :update_email_and_nin
        })

      assert both_item.sub_action == :update_email_and_nin
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
