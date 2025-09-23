defmodule CapwaySync.Reactor.V1.Steps.CapwaySubscribers do
  use Reactor.Step
  alias CapwaySync.Soap.GenerateReport
  alias CapwaySync.Soap.ResponseHandler

  @impl true
  def run(_map, _context, _options) do
    with {:ok, xml_data} <- GenerateReport.generate_report(),
         {:ok, capway_subscribers} <- Saxy.parse_string(xml_data, ResponseHandler, []),
         false <- capway_subscribers == [] do
      {:ok, capway_subscribers}
    else
      _ ->
        {:error, "unknown error fetching capway subscribers"}
    end
  end

  @impl true
  def compensate(error, _arguments, _context, _options) do
    :retry
  end

  @impl true
  def undo(_map, _context, _options) do
    :ok
  end
end
