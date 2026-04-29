defmodule CapwaySync.Dynamodb.ActionItemRepositoryV2 do
  alias CapwaySync.Models.Dynamodb.ActionItem
  alias CapwaySync.Dynamodb.Client

  require Logger

  @table_name_env "ACTION_ITEMS_TABLE"
  @default_table_name "capway-sync-action-items"

  @spec store_action_item(ActionItem.t()) :: :ok | {:error, any()}
  def store_action_item(%ActionItem{} = action_item) do
    table_name = System.get_env(@table_name_env, @default_table_name)

    item = %{
      "id" => create_id(action_item),
      "trinity_subscriber_id" => action_item.trinity_subscriber_id,
      "trinity_subscription_id" => action_item.trinity_subscription_id,
      "capway_customer_id" => action_item.capway_customer_id,
      "capway_contract_ref" => action_item.capway_contract_ref,
      "capway_contract_guid" => action_item.capway_contract_guid,
      "national_id" => action_item.national_id,
      "created_at" => action_item.created_at,
      "timestamp" => action_item.timestamp,
      "action" => action_item.action,
      "sub_action" => action_item.sub_action,
      "status" => Atom.to_string(action_item.status),
      "comment" => action_item.comment
    }

    # IO.inspect(item, label: "DynamoDB Item to Store")

    case Client.put_item(table_name, item) do
      {:ok, _response} ->
        # Logger.info("Successfully stored action item #{action_item.id} in DynamoDB")
        :ok

      {:error, reason} ->
        Logger.error(
          "Failed to store action item #{action_item.id} in DynamoDB: #{inspect(reason)}"
        )

        {:error, reason}
    end
  end

  defp create_id(%{
         created_at: created_at,
         action: action,
         trinity_subscriber_id: nil,
         trinity_subscription_id: nil,
         capway_customer_id: nil,
         capway_contract_ref: nil
       }) do
    "#{created_at}:#{action}:ERROR_NO_REF_AVAILABLE:#{UUID.uuid4()}"
  end

  defp create_id(%{
         created_at: created_at,
         action: action,
         trinity_subscriber_id: subscriber_id,
         trinity_subscription_id: nil,
         capway_customer_id: nil,
         capway_contract_ref: nil
       }) do
    "#{created_at}:#{action}:tuid:#{subscriber_id}"
  end

  defp create_id(%{
         created_at: created_at,
         action: action,
         trinity_subscription_id: subscription_id,
         capway_customer_id: nil,
         capway_contract_ref: nil
       }) do
    "#{created_at}:#{action}:tsuid:#{subscription_id}"
  end

  defp create_id(%{
         created_at: created_at,
         action: action,
         capway_customer_id: capway_customer_id,
         capway_contract_ref: nil
       }) do
    "#{created_at}:#{action}:cuid:#{capway_customer_id}"
  end

  defp create_id(%{
         created_at: created_at,
         action: action,
         capway_contract_ref: capway_contract_ref
       }) do
    "#{created_at}:#{action}:cref:#{capway_contract_ref}"
  end
end
