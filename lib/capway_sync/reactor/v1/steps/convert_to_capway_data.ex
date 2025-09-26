defmodule CapwaySync.Reactor.V1.Steps.ConvertToCapwayData do
  use Reactor.Step

  @impl true
  def run(data, _context, _options) do
    capway_data =
      Enum.map(
        data.trinity_subscribers,
        fn %{
             personal_number: personal_number,
             subscription: subscription
           } =
             subscriber ->
          %CapwaySync.Models.CapwaySubscriber{
            customer_ref: subscription.id,
            id_number: personal_number,
            name: nil,
            contract_ref_no: subscription.id,
            reg_date: nil,
            start_date: nil,
            end_date: subscription.end_date,
            active: subscription.status == :active,
            raw_data: subscriber,
            origin: :trinity
          }
        end
      )

    {:ok, capway_data}
  end


  @impl true
  def undo(_map, _context, _options, _step_options) do
    :ok
  end
end
