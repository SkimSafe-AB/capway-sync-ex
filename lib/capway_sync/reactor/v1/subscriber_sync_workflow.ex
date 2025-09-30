defmodule CapwaySync.Reactor.V1.SubscriberSyncWorkflow do
  use Reactor

  alias CapwaySync.Reactor.V1.Steps.{
    CapwaySubscribers,
    CompareData,
    ConvertToCapwayData,
    SuspendAccounts,
    TrinitySubscribers,
    UnsuspendAccounts
  }
  alias CapwaySync.Models.GeneralSyncReport
  alias CapwaySync.Dynamodb.GeneralSyncReportRepository

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

  # Converts Trinity subscriber data to Capway-compatible format.
  # Transforms Trinity data structure to match Capway's expected schema
  # for proper comparison and synchronization.
  step(:convert_to_capway_data, ConvertToCapwayData) do
    argument(:trinity_subscribers, result(:fetch_trinity_data))
    max_retries(3)
    async?(true)

    # run(&ConvertToCapwayData.run/1)
  end

  # Fetches existing subscriber data from Capway system.
  # Retrieves current subscriber records from Capway to compare
  # against Trinity data for synchronization.
  step(:fetch_capway_data, CapwaySubscribers) do
    max_retries(3)
    async?(true)
  end

  # Compares Trinity and Capway subscriber data.
  # Identifies accounts that exist in both systems, missing in Capway
  # (to be added), and missing in Trinity (to be removed).
  # Uses customer_ref for both datasets since ConvertToCapwayData maps subscription.id to customer_ref
  step :compare_data do
    argument(:trinity_subscribers, result(:convert_to_capway_data))
    argument(:capway_subscribers, result(:fetch_capway_data))
    max_retries(2)

    # Both datasets are CapwaySubscriber structs after conversion, so use the same key
    # Trinity converted data: CapwaySubscriber with id_number from personal_number
    # Capway SOAP data: CapwaySubscriber with id_number from SOAP response
    run(fn args, context ->
      CompareData.run(args, context, trinity_key: :id_number, capway_key: :id_number)
    end)
  end

  # Identifies accounts that should be suspended.
  # Analyzes accounts existing in both systems and flags those
  # with collection >= 2 for suspension.
  step(:suspend_accounts, SuspendAccounts) do
    argument(:comparison_result, result(:compare_data))
    max_retries(2)
  end

  # Identifies accounts that should be unsuspended.
  # Analyzes accounts existing in both systems and flags those
  # with collection = 0 AND unpaid_invoices = 0 for unsuspension.
  step(:unsuspend_accounts, UnsuspendAccounts) do
    argument(:comparison_result, result(:compare_data))
    max_retries(2)
  end

  # Final step that processes and logs all workflow results.
  # Creates a GeneralSyncReport struct with all workflow data and logs summary.
  step :process_results do
    argument(:start_time, result(:start_timer))
    argument(:comparison_result, result(:compare_data))
    argument(:suspend_result, result(:suspend_accounts))
    argument(:unsuspend_result, result(:unsuspend_accounts))

    run(fn args, _context ->
      # Create comprehensive report struct from all workflow results
      end_time = System.monotonic_time(:millisecond)

      report = GeneralSyncReport.from_workflow_results(
        args.comparison_result,
        args.suspend_result,
        args.unsuspend_result,
        args.start_time,
        end_time
      )

      # Log the formatted report summary
      Logger.info(GeneralSyncReport.summary(report))

      # Log additional details if there are accounts to process
      if report.missing_capway_count > 0 do
        Logger.info("➕ Subscribers to be added to Capway:")
        Enum.each(report.missing_in_capway, fn sub ->
          Logger.info("     - #{Map.get(sub, :id_number, "N/A")}: #{Map.get(sub, :name, "Unknown")}")
        end)
      end

      if report.missing_trinity_count > 0 do
        Logger.info("➖ Subscribers to be removed from Capway:")
        Enum.each(report.missing_in_trinity, fn sub ->
          Logger.info("     - #{Map.get(sub, :id_number, "N/A")}: #{Map.get(sub, :name, "Unknown")}")
        end)
      end

      if report.suspend_count > 0 do
        Logger.info("🔒 Accounts to suspend (collection >= #{report.suspend_threshold}):")
        Enum.each(report.suspend_accounts, fn sub ->
          Logger.info("     - #{Map.get(sub, :id_number, "N/A")}: #{Map.get(sub, :name, "Unknown")} (collection: #{Map.get(sub, :collection, "N/A")})")
        end)
      end

      if report.unsuspend_count > 0 do
        Logger.info("🔓 Accounts to unsuspend (collection=0, unpaid_invoices=0):")
        Enum.each(report.unsuspend_accounts, fn sub ->
          Logger.info("     - #{Map.get(sub, :id_number, "N/A")}: #{Map.get(sub, :name, "Unknown")}")
        end)
      end

      Logger.info("✅ SubscriberSyncWorkflow completed successfully in #{report.execution_duration_formatted}")

      # Store the report to DynamoDB
      case GeneralSyncReportRepository.store_report(report) do
        {:ok, report_id} ->
          Logger.info("📝 GeneralSyncReport stored to DynamoDB with ID: #{report_id}")
          # Return report with metadata about storage
          report_with_id = %{report | created_at: report.created_at}
          {:ok, %{report: report_with_id, report_id: report_id, stored: true}}

        {:error, reason} ->
          Logger.error("❌ Failed to store GeneralSyncReport to DynamoDB: #{inspect(reason)}")
          # Still return the report even if storage failed
          {:ok, %{report: report, report_id: nil, stored: false, storage_error: reason}}
      end
    end)
  end

  return(:process_results)
end
