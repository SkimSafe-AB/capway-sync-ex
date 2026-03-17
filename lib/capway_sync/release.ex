defmodule CapwaySync.Release do
  @moduledoc """
  Release tasks that can be invoked via `bin/run_sync` or
  `bin/capway_sync eval "CapwaySync.Release.run_sync()"`.
  """

  require Logger

  @doc """
  Triggers the subscriber sync workflow.
  Ensures all required applications are started before running.
  """
  def run_sync do
    start_applications()
    Logger.info("Starting subscriber sync workflow via release task")

    case Reactor.run(CapwaySync.Reactor.V1.SubscriberSyncWorkflow, %{}) do
      {:ok, result} ->
        Logger.info("Subscriber sync workflow completed successfully")
        result

      {:error, reason} ->
        Logger.error("Subscriber sync workflow failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp start_applications do
    Application.ensure_all_started(:reactor)
    Application.ensure_all_started(:capway_sync)
    load_modules()
  end

  defp load_modules do
    Code.ensure_loaded!(CapwaySync.Models.CapwaySubscriber)
    Code.ensure_loaded!(CapwaySync.Models.Subscribers.Canonical)
    Code.ensure_loaded!(CapwaySync.Models.Trinity.Subscriber)
    Code.ensure_loaded!(CapwaySync.Models.Trinity.Subscription)
    Code.ensure_loaded!(CapwaySync.Models.Trinity.Subscriber.Metadata)
    Code.ensure_loaded!(CapwaySync.Models.Dynamodb.ActionItem)
  end
end
