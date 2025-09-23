defmodule CapwaySync.Reactor.V1.Steps.TrinitySubscribers do
  use Reactor.Step
  alias CapwaySync.Ecto.TrinitySubscribers

  @impl true
  def run(_map, _context, _options) do
    {:ok, TrinitySubscribers.list_subscribers(true)}
  end

  @impl true
  def undo(_map, _context, _options) do
    :ok
  end
end
