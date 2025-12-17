defmodule CapwaySync.Dynamodb.GeneralSyncReportRepositoryV2 do
  alias CapwaySync.Models.Dynamodb.ActionItem
  alias CapwaySync.Dynamodb.Client

  require Logger

  @table_name_env "SYNC_REPORTS_TABLE"
  @default_table_name "capway-sync-reports"

  @spec store_report(map(), map(), map()) :: :ok | {:error, any()}
  def store_report(actions, trinity, capway) do
    table_name = System.get_env(@table_name_env, @default_table_name)

    Logger.info("actions: #{inspect(actions)}")
    Logger.info("trinity: #{inspect(trinity)}")
    Logger.info("capway: #{inspect(capway)}")
    Logger.info("Capway Active Contracts: #{inspect(Map.get(capway, :active_subscribers))}")

    Logger.info(
      "Capway Active Contracts: #{inspect(Map.get(capway, :active_subscribers) |> map_size())}"
    )

    report = %{
      "id" => UUID.uuid4(),
      "created_at" => Date.utc_today() |> Date.to_string(),
      "capway" => %{
        "cancelled" => get_map_length(Map.get(capway, :cancelled_subscribers)),
        "active" => get_map_length(Map.get(capway, :active_subscribers)),
        "above_collector_threshold" => %{
          "count" => get_map_length(Map.get(capway, :above_collector_threshold)),
          "ids" => Map.keys(Map.get(capway, :above_collector_threshold))
        },
        "orphaned" => get_map_length(Map.get(capway, :orphaned_subscribers)),
        "actions" => %{
          "cancel_contracts" => %{
            "count" => get_map_length(Map.get(actions.capway, :cancel_contracts, %{})),
            "ids" => Map.keys(Map.get(actions.capway, :cancel_contracts, %{}))
          },
          "update_contracts" => %{
            "count" => get_map_length(Map.get(actions.capway, :update_contracts, %{})),
            "ids" => Map.keys(Map.get(actions.capway, :update_contracts, %{}))
          },
          "create_contracts" => %{
            "count" => get_map_length(Map.get(actions.capway, :create_contracts, %{})),
            "ids" => Map.keys(Map.get(actions.capway, :create_contracts, %{}))
          }
        }
      },
      "trinity" => %{
        "cancelled" => get_map_length(Map.get(trinity, :cancelled_subscribers)),
        "active" => get_map_length(Map.get(trinity, :active_subscribers)),
        "locked" => get_map_length(Map.get(trinity, :locked_subscribers)),
        "actions" => %{
          "cancel_accounts" => %{
            "count" => get_map_length(Map.get(actions.trinity, :cancel_accounts, %{})),
            "ids" => Map.keys(Map.get(actions.trinity, :cancel_accounts, %{}))
          },
          "suspend_accounts" => %{
            "count" => get_map_length(Map.get(actions.trinity, :suspend_accounts, %{})),
            "ids" => Map.keys(Map.get(actions.trinity, :suspend_accounts, %{}))
          }
        }
      }
    }

    case Client.put_item(table_name, report) do
      {:ok, _response} ->
        Logger.info("Successfully stored sync report #{report["id"]} in DynamoDB")
        {:ok, report["id"]}

      {:error, reason} ->
        Logger.error(
          "Failed to store sync report #{report["id"]} in DynamoDB: #{inspect(reason)}"
        )

        {:error, reason}
    end
  end

  defp get_map_length(map) when is_map(map), do: map_size(map)
  defp get_map_length(_), do: 0
end
