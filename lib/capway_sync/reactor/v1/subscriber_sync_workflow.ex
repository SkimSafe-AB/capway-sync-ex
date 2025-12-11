defmodule CapwaySync.Reactor.V1.SubscriberSyncWorkflow do
  use Reactor

  alias CapwaySync.Reactor.V1.Steps.{
    CapwaySubscribers,
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
  alias CapwaySync.Dynamodb.{GeneralSyncReportRepository, ActionItemRepository}

  require Logger

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
  step(:fetch_capway_data, CapwaySubscribers) do
    max_retries(3)
    async?(true)
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

  # # Compares Trinity and Capway subscriber data in canonical format.
  # # Identifies accounts that exist in both systems, missing in Capway
  # # (to be added), missing in Trinity (to be removed), and those needing
  # # contract cancellation due to payment method changes.
  # step :compare_data do
  #   argument(:trinity_subscribers, result(:convert_to_canonical_data))
  #   argument(:capway_data, result(:fetch_capway_data))
  #   max_retries(2)

  #   # Both datasets are Subscribers.Canonical structs after conversion
  #   run(fn args, context ->
  #     # Extract canonical subscribers for comparison
  #     capway_subscribers = args.capway_data.canonical

  #     comparison_args = %{
  #       trinity_subscribers: args.trinity_subscribers,
  #       capway_subscribers: capway_subscribers
  #     }

  #     CompareData.run(comparison_args, context, trinity_key: :id_number, capway_key: :id_number)
  #   end)
  # end

  # # Prepares data for suspend/unsuspend analysis by combining comparison results
  # # with raw Capway data that contains collection information.
  # # Enriches Capway data with Trinity subscription_type and status.
  # step :prepare_suspend_unsuspend_data do
  #   argument(:comparison_result, result(:compare_data))
  #   argument(:capway_data, result(:fetch_capway_data))
  #   argument(:trinity_canonical, result(:convert_to_canonical_data))
  #   max_retries(2)

  #   run(fn args, _context ->
  #     # Create a map of Trinity canonical data by id_number for quick lookup
  #     trinity_map = Map.new(args.trinity_canonical, fn sub -> {sub.id_number, sub} end)

  #     # Get the IDs of accounts that exist in both systems
  #     existing_both_ids =
  #       args.comparison_result.existing_in_both
  #       |> Enum.map(& &1.id_number)
  #       |> MapSet.new()

  #     # Filter raw Capway data and enrich with Trinity subscription_type and status
  #     existing_both_enriched =
  #       args.capway_data.raw
  #       |> Enum.filter(fn capway_sub ->
  #         MapSet.member?(existing_both_ids, capway_sub.id_number)
  #       end)
  #       |> Enum.map(fn capway_sub ->
  #         # Get Trinity data for this subscriber
  #         trinity_data = Map.get(trinity_map, capway_sub.id_number)

  #         # Enrich Capway data with Trinity subscription_type and status
  #         if trinity_data do
  #           Map.merge(capway_sub, %{
  #             subscription_type: trinity_data.subscription_type,
  #             status: trinity_data.status
  #           })
  #         else
  #           capway_sub
  #         end
  #       end)

  #     # Create a modified comparison result with enriched data for suspend/unsuspend
  #     modified_comparison_result =
  #       Map.put(args.comparison_result, :existing_in_both, existing_both_enriched)

  #     {:ok, modified_comparison_result}
  #   end)
  # end

  # # Identifies accounts that should be suspended.
  # # Analyzes accounts existing in both systems and flags those
  # # with collection >= 2 for suspension.
  # step(:suspend_accounts, SuspendAccounts) do
  #   argument(:comparison_result, result(:prepare_suspend_unsuspend_data))
  #   max_retries(2)
  # end

  # # Identifies accounts that should be unsuspended.
  # # Analyzes accounts existing in both systems and flags those
  # # with collection = 0 AND unpaid_invoices = 0 for unsuspension.
  # step(:unsuspend_accounts, UnsuspendAccounts) do
  #   argument(:comparison_result, result(:prepare_suspend_unsuspend_data))
  #   max_retries(2)
  # end

  # # Identifies Capway contracts that need cancellation.
  # # Analyzes subscribers that exist in both systems but have changed
  # # payment method from "capway" to something else in Trinity.
  # step(:cancel_capway_contracts, CancelCapwayContracts) do
  #   argument(:comparison_result, result(:compare_data))
  #   max_retries(2)
  # end

  # # Exports Capway subscribers with unpaid invoices and collections to CSV.
  # # Creates a CSV file containing subscribers that have either unpaid invoices > 0
  # # or collections > 0 for further analysis and reporting.
  # step :capway_export_subscribers_csv do
  #   argument(:capway_data, result(:fetch_capway_data))

  #   run(fn args, context ->
  #     # Extract raw Capway data for CSV export
  #     capway_raw_data = args.capway_data.raw

  #     # Call the export step with raw data
  #     CapwayExportSubscribers.run(%{capway_data: capway_raw_data}, context)
  #   end)

  #   max_retries(2)
  # end

  # # Final step that processes and logs all workflow results.
  # # Creates a GeneralSyncReport struct with all workflow data and logs summary.
  # step :process_results do
  #   argument(:start_time, result(:start_timer))
  #   argument(:comparison_result, result(:compare_data))
  #   argument(:suspend_result, result(:suspend_accounts))
  #   argument(:unsuspend_result, result(:unsuspend_accounts))
  #   argument(:cancel_result, result(:cancel_capway_contracts))
  #   argument(:capway_data, result(:fetch_capway_data))
  #   argument(:csv_export_result, result(:capway_export_subscribers_csv))

  #   run(fn args, _context ->
  #     # Create comprehensive report struct from all workflow results
  #     end_time = System.monotonic_time(:millisecond)

  #     # Merge cancel_contracts from suspend_result with cancel_capway_contracts
  #     merged_cancel_contracts =
  #       (args.cancel_result.cancel_capway_contracts || []) ++
  #         (args.suspend_result.cancel_contracts || [])

  #     merged_cancel_ids =
  #       Enum.map(merged_cancel_contracts, fn
  #         %{trinity_id: id} when not is_nil(id) -> id
  #         %{customer_ref: id} when not is_nil(id) -> id
  #         # Fallback
  #         %{capway_id: id} when not is_nil(id) -> id
  #         %{id_number: id} when not is_nil(id) -> id
  #         _ -> nil
  #       end)
  #       |> Enum.reject(&is_nil/1)

  #     merged_cancel_result = %{
  #       cancel_capway_contracts: merged_cancel_contracts,
  #       cancel_capway_contracts_ids: merged_cancel_ids,
  #       cancel_capway_count:
  #         (args.cancel_result.cancel_capway_count || 0) +
  #           (args.suspend_result.cancel_contracts_count || 0)
  #     }

  #     report =
  #       GeneralSyncReport.from_workflow_results(
  #         args.comparison_result,
  #         args.suspend_result,
  #         args.unsuspend_result,
  #         merged_cancel_result,
  #         args.capway_data.raw,
  #         args.start_time,
  #         end_time
  #       )

  #     # Log the formatted report summary
  #     Logger.info(GeneralSyncReport.summary(report))

  #     # Log additional details if there are accounts to process
  #     # if report.missing_capway_count > 0 do
  #     #   Logger.info("➕ Subscribers to be added to Capway:")
  #     #   Enum.each(report.missing_in_capway, fn id ->
  #     #     Logger.info("     - ID: #{id}")
  #     #   end)
  #     # end

  #     # if report.missing_trinity_count > 0 do
  #     #   Logger.info("➖ Subscribers to be removed from Capway:")
  #     #   Enum.each(report.missing_in_trinity, fn id ->
  #     #     Logger.info("     - ID: #{id}")
  #     #   end)
  #     # end

  #     # if report.suspend_count > 0 do
  #     #   Logger.info("🔒 Accounts to suspend (collection >= #{report.suspend_threshold}):")
  #     #   Enum.each(report.suspend_accounts, fn id ->
  #     #     Logger.info("     - ID: #{id}")
  #     #   end)
  #     # end

  #     # if report.unsuspend_count > 0 do
  #     #   Logger.info("🔓 Accounts to unsuspend (collection=0, unpaid_invoices=0):")
  #     #   Enum.each(report.unsuspend_accounts, fn id ->
  #     #     Logger.info("     - ID: #{id}")
  #     #   end)
  #     # end

  #     # if report.cancel_capway_count > 0 do
  #     #   Logger.info("🚫 Capway contracts to cancel (payment method changed):")
  #     #   Enum.each(report.cancel_capway_contracts, fn id ->
  #     #     Logger.info("     - ID: #{id}")
  #     #   end)
  #     # end

  #     # Log CSV export results
  #     Logger.info("📊 CSV Export Results:")
  #     Logger.info("   - File: #{args.csv_export_result.csv_file_path}")
  #     Logger.info("   - Total exported: #{args.csv_export_result.total_exported}")

  #     Logger.info(
  #       "   - With unpaid invoices: #{args.csv_export_result.customers_with_unpaid_invoices}"
  #     )

  #     Logger.info("   - With collections: #{args.csv_export_result.customers_with_collections}")

  #     Logger.info(
  #       "✅ SubscriberSyncWorkflow completed successfully in #{report.execution_duration_formatted}"
  #     )

  #     # Store the report to DynamoDB
  #     case GeneralSyncReportRepository.store_report(report) do
  #       {:ok, report_id} ->
  #         Logger.info("📝 GeneralSyncReport stored to DynamoDB with ID: #{report_id}")
  #         # Return report with metadata about storage
  #         report_with_id = %{report | created_at: report.created_at}

  #         {:ok,
  #          %{
  #            report: report_with_id,
  #            report_id: report_id,
  #            stored: true,
  #            csv_export: args.csv_export_result
  #          }}

  #       {:error, reason} ->
  #         Logger.error("❌ Failed to store GeneralSyncReport to DynamoDB: #{inspect(reason)}")
  #         # Still return the report even if storage failed
  #         {:ok,
  #          %{
  #            report: report,
  #            report_id: nil,
  #            stored: false,
  #            storage_error: reason,
  #            csv_export: args.csv_export_result
  #          }}
  #     end
  #   end)
  # end

  # # Stores individual action items to DynamoDB for tracking and processing.
  # # Creates ActionItem records for each required action (suspend, unsuspend, sync_to_capway)
  # # identified in the sync workflow results.
  # step :store_action_items do
  #   argument(:report_result, result(:process_results))

  #   run(fn args, _context ->
  #     report = args.report_result.report

  #     # Store individual action items to DynamoDB
  #     case ActionItemRepository.store_action_items_from_report(report) do
  #       {:ok, action_result} ->
  #         Logger.info(
  #           "📋 ActionItems stored: #{action_result.stored} items, #{action_result.failed} failed"
  #         )

  #         # Combine with previous result
  #         combined_result =
  #           Map.merge(args.report_result, %{
  #             action_items_stored: action_result.stored,
  #             action_items_failed: action_result.failed,
  #             action_items_ids: action_result.item_ids
  #           })

  #         {:ok, combined_result}

  #       {:error, reason} ->
  #         Logger.error("❌ Failed to store ActionItems: #{inspect(reason)}")

  #         # Still return successful result but with action items error
  #         combined_result =
  #           Map.merge(args.report_result, %{
  #             action_items_stored: 0,
  #             action_items_failed: 0,
  #             action_items_error: reason
  #           })

  #         {:ok, combined_result}
  #     end
  #   end)
  # end

  # return(:store_action_items)
end
