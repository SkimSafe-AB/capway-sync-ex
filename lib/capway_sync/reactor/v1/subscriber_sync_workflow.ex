defmodule CapwaySync.Reactor.V1.SubscriberSyncWorkflow do
  use Reactor

  alias CapwaySync.Reactor.V1.Steps.{
    CachedCapwaySubscribers,
    CapwayExportSubscribers,
    CancelCapwayContracts,
    CompareDataV2,
    ConvertToCanonicalData,
    GroupSubscribers,
    SuspendAccounts,
    TrinitySubscribers,
    UnsuspendAccounts
  }

  alias CapwaySync.Models.GeneralSyncReport
  alias CapwaySync.Dynamodb.ActionItemRepositoryV2
  alias CapwaySync.Dynamodb.CapwayContractRepository
  alias CapwaySync.Dynamodb.GeneralSyncReportRepositoryV2

  require Logger

  @doc false
  defp store_action_items(action_items_map, label) do
    Enum.each(action_items_map, fn {_id, action_item} ->
      case ActionItemRepositoryV2.store_action_item(action_item) do
        :ok ->
          Logger.debug("Stored #{label} action item for subscriber #{action_item.national_id}")

        {:error, reason} ->
          Logger.error(
            "Failed to store #{label} action item for subscriber #{action_item.national_id}: #{inspect(reason)}"
          )
      end
    end)
  end

  # Start timer for workflow execution tracking
  step :start_timer do
    run(fn _args, _context ->
      start_time = System.monotonic_time(:millisecond)
      Logger.info("🚀 Starting SubscriberSyncWorkflow execution at #{DateTime.utc_now()}")
      {:ok, start_time}
    end)
  end

  # Fetches subscriber data from the Trinity system.
  # This is the first step that retrieves all subscriber records from Trinity database
  # which serves as the master data source for synchronization.
  step(:fetch_trinity_data, TrinitySubscribers) do
    max_retries(3)
    async?(true)
  end

  # Fetches existing subscriber data from Capway system.
  # Retrieves current subscriber records from Capway to compare
  # against Trinity data for synchronization.
  step(:fetch_capway_data, CachedCapwaySubscribers) do
    max_retries(3)
    async?(true)
  end

  # Stores each Capway contract as its own DynamoDB item for fast lookups.
  step(:store_capway_contracts) do
    argument(:capway_data, result(:fetch_capway_data))

    run(fn args, _context ->
      subscribers = args.capway_data
      total = length(subscribers)

      nil_contract_ref_count =
        Enum.count(subscribers, fn s -> is_nil(s.contract_ref_no) end)

      unique_contract_refs =
        subscribers
        |> Enum.map(& &1.contract_ref_no)
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq()
        |> length()

      duplicate_contract_refs = total - nil_contract_ref_count - unique_contract_refs

      Logger.info(
        "📊 Capway contracts pre-store breakdown: " <>
          "total=#{total}, " <>
          "nil_contract_ref_no=#{nil_contract_ref_count}, " <>
          "unique_contract_refs=#{unique_contract_refs}, " <>
          "duplicate_contract_refs=#{duplicate_contract_refs}"
      )

      if nil_contract_ref_count > 0 do
        nil_samples =
          subscribers
          |> Enum.filter(fn s -> is_nil(s.contract_ref_no) end)
          |> Enum.take(5)
          |> Enum.map(fn s ->
            "customer_ref=#{s.customer_ref}, id_number=#{s.id_number}, name=#{s.name}"
          end)

        Logger.warning(
          "⚠️ #{nil_contract_ref_count} subscribers have nil contract_ref_no (will be skipped). " <>
            "Samples: #{inspect(nil_samples)}"
        )
      end

      {stored, errors, skipped} = CapwayContractRepository.store_contracts(subscribers)

      Logger.info(
        "✅ Capway contracts post-store: " <>
          "stored=#{stored}, errors=#{errors}, skipped=#{skipped}, " <>
          "total_input=#{total}"
      )

      {:ok, {stored, errors, skipped}}
    end)
  end

  # Converts Trinity subscriber data to canonical format.
  # Transforms Trinity data structure to a unified canonical format
  # for proper comparison with Capway data.
  step(:convert_to_canonical_data, ConvertToCanonicalData) do
    argument(:trinity_subscribers, result(:fetch_trinity_data))
    argument(:capway_data, result(:fetch_capway_data))
    max_retries(3)
    async?(false)
  end

  step(:group_subscribers, GroupSubscribers) do
    argument(:data, result(:convert_to_canonical_data))
    max_retries(2)
  end

  step(:compare_data, CompareDataV2) do
    argument(:data, result(:group_subscribers))
    max_retries(2)
  end

  step(:dynamodb_store_action_items) do
    argument(:result, result(:compare_data))

    run(fn args, _context ->
      Logger.info(
        "Storing action items to DynamoDB for identified subscriber synchronization actions"
      )

      Logger.info(
        "Number of Capway Cancel Contracts: #{map_size(args.result.actions.capway.cancel_contracts)}"
      )

      Logger.info(
        "Number of Capway Create Contracts: #{map_size(args.result.actions.capway.create_contracts)}"
      )

      Logger.info(
        "Number of Capway Update Contracts: #{map_size(args.result.actions.capway.update_contracts)}"
      )

      Logger.info(
        "Number of Capway Update Customers: #{map_size(args.result.actions.capway.update_customers)}"
      )

      Logger.info(
        "Number of Trinity Cancel Accounts: #{map_size(args.result.actions.trinity.cancel_accounts)}"
      )

      Logger.info(
        "Number of Trinity Suspend Accounts: #{map_size(args.result.actions.trinity.suspend_accounts)}"
      )

      store_action_items(args.result.actions.capway.cancel_contracts, "capway cancel")
      store_action_items(args.result.actions.capway.create_contracts, "capway create")
      store_action_items(args.result.actions.capway.update_contracts, "capway update contract")
      store_action_items(args.result.actions.capway.update_customers, "capway update customer")
      store_action_items(args.result.actions.trinity.cancel_accounts, "trinity cancel")
      store_action_items(args.result.actions.trinity.suspend_accounts, "trinity suspend")

      {:ok, :done}
    end)
  end

  step(:dynamodb_store_report) do
    argument(:result, result(:compare_data))
    # argument(:data, result(:group_subscribers))

    run(fn args, _context ->
      case GeneralSyncReportRepositoryV2.store_report(
             args.result.actions,
             args.result.source.trinity,
             args.result.source.capway
           ) do
        {:ok, report_id} ->
          Logger.info("Successfully stored GeneralSyncReport to DynamoDB with ID: #{report_id}")
          {:ok, report_id}

        {:error, reason} ->
          Logger.error("Failed to store GeneralSyncReport to DynamoDB: #{inspect(reason)}")
          {:error, reason}
      end
    end)
  end
end
