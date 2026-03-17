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
      {:ok, _result} ->
        Logger.info("Subscriber sync workflow completed successfully")
        System.halt(0)

      {:error, reason} ->
        Logger.error("Subscriber sync workflow failed: #{inspect(reason)}")
        System.halt(1)
    end
  end

  defp start_applications do
    Application.ensure_all_started(:capway_sync)

    {:ok, modules} = :application.get_key(:capway_sync, :modules)
    Enum.each(modules, &Code.ensure_loaded!/1)
  end
end
