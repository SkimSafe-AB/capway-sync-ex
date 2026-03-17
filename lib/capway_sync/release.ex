defmodule CapwaySync.Release do
  @moduledoc """
  Release tasks that can be invoked via `bin/run_sync` or
  `bin/capway_sync eval "CapwaySync.Release.run_sync()"`.
  """

  require Logger

  @doc """
  Triggers the subscriber sync workflow.
  """
  def run_sync do
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
end
