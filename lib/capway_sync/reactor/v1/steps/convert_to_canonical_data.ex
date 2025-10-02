defmodule CapwaySync.Reactor.V1.Steps.ConvertToCanonicalData do
  use Reactor.Step
  alias CapwaySync.Models.Subscribers.Canonical

  @impl true
  def run(data, _context, _options) do
    canonical_data = Canonical.from_trinity_list(data.trinity_subscribers)
    {:ok, canonical_data}
  end

  @impl true
  def undo(_map, _context, _options, _step_options) do
    :ok
  end
end
