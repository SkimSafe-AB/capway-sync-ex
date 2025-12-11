defmodule CapwaySync.Reactor.V1.Steps.ConvertToCanonicalData do
  use Reactor.Step
  alias CapwaySync.Models.Subscribers.Canonical

  @impl true
  def run(data, _context, _options) do
    trinity_canonical_data = Canonical.from_trinity_list(data.trinity_subscribers)
    capway_canonical_data = Canonical.from_capway_list(data.capway_data)

    canonical_data = %{
      trinity: trinity_canonical_data,
      capway: capway_canonical_data
    }

    {:ok, canonical_data}
  end

  @impl true
  def undo(_map, _context, _options, _step_options) do
    :ok
  end
end
