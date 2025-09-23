defmodule CapwaySync.Reactor.V1.SubscriberSyncWorkflow do
  use Reactor

  alias CapwaySync.Reactor.V1.Steps.CapwaySubscribers
  alias CapwaySync.Reactor.V1.Steps.TrinitySubscribers

  step(:fetch_trinity_data, TrinitySubscribers) do
    max_retries(3)
    async?(true)
  end

  step(:fetch_capway_data, CapwaySubscribers) do
    max_retries(3)
    async?(true)
  end

  step :process_data do
    argument(:trinity_subscribers, result(:fetch_trinity_data))
    argument(:capway_subscribers, result(:fetch_capway_data))

    run(fn args, _context ->
      {:ok, :processed}
    end)
  end

  return(:process_data)
end
