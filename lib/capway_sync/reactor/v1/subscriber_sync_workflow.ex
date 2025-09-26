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

  require Logger

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
  step(:compare_data, CompareData) do
    argument(:trinity_subscribers, result(:convert_to_capway_data))
    argument(:capway_subscribers, result(:fetch_capway_data))
    max_retries(2)
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
  # Logs data comparison statistics, suspend/unsuspend analysis results,
  # and detailed information about accounts to be modified.
  step :process_results do
    argument(:comparison_result, result(:compare_data))
    argument(:suspend_result, result(:suspend_accounts))
    argument(:unsuspend_result, result(:unsuspend_accounts))

    run(fn args, _context ->
      result = args.comparison_result

      Logger.info("Data comparison results:")
      Logger.info("- Total Trinity subscribers: #{result.total_trinity}")
      Logger.info("- Total Capway subscribers: #{result.total_capway}")
      Logger.info("- Missing in Capway: #{result.missing_capway_count}")
      Logger.info("- Missing in Trinity: #{result.missing_trinity_count}")

      if result.missing_capway_count > 0 do
        Logger.info("Subscribers to be added to Capway:")

        Enum.each(result.missing_in_capway, fn sub ->
          Logger.info("  - #{sub.id || "N/A"}: #{Map.get(sub, :name, "Unknown")}")
        end)
      end

      if result.missing_trinity_count > 0 do
        Logger.info("Subscribers to be removed from Capway:")

        Enum.each(result.missing_in_trinity, fn sub ->
          Logger.info("  - #{sub.customer_ref || "N/A"}: #{Map.get(sub, :name, "Unknown")}")
        end)
      end

      {:ok, result}
    end)
  end

  return(:process_results)
end
