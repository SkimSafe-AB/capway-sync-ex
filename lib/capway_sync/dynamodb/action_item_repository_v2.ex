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
      "id" => action_item.id || UUID.uuid4(),
      "trinity_subscriber_id" => action_item.trinity_subscriber_id,
      "national_id" => action_item.national_id,
      "created_at" => action_item.created_at,
      "timestamp" => action_item.timestamp,
      "action" => action_item.action,
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
end
