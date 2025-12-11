defmodule CapwaySync.Reactor.V1.Steps.GroupSubscribers do
  use Reactor.Step
  require Logger
  alias CapwaySync.Models.Subscribers.Cannonical.Helper

  @impl Reactor.Step
  def run(args, _context, _options) do
    Logger.info("Starting to group subscribers into categories")
    Logger.info("Data keys available: #{inspect(Map.keys(args.data))}")
    capway_cannonical_data = Map.get(args.data, :capway, [])
    trinity_cannonical_data = Map.get(args.data, :trinity, [])

    grouped_capway = Helper.group(capway_cannonical_data, :capway)
    grouped_trinity = Helper.group(trinity_cannonical_data, :trinity)
    Logger.info("==============================================")
    Logger.info("Grouped Capway Subscribers: #{inspect(grouped_capway)}")
    Logger.info("Grouped Trinity Subscribers: #{inspect(grouped_trinity)}")
    Logger.info("==============================================")

    {:ok,
     %{
       capway: grouped_capway,
       trinity: grouped_trinity
     }}
  end
end
