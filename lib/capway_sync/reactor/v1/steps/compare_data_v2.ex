defmodule CapwaySync.Reactor.V1.Steps.CompareDataV2 do
  alias ElixirSense.Log
  use Reactor.Step
  require Logger

  @doc """
  The args map is expected to have the following structure
  in terms of Cannonical data, ie they are equaly the same
  but from different sources:

    %{
  trinity: [%Canonical{}, ...],
  capway: [%Canonical{}, ...]
  }
  """
  @impl Reactor.Step
  def run(args, _context, _options) do
    Logger.info("==============================================")
    Logger.info("DATA WHEN COMPARING: #{inspect(args)}")
    Logger.info("==============================================")
    trinity_subscriber_data = Map.get(args.data, :trinity, [])
    capway_subscriber_data = Map.get(args.data, :capway, [])
    Logger.info("Starting data comparison between Trinity and Capway subscribers")

    Logger.info(
      "Trinity active subscriber mapset: #{inspect(trinity_subscriber_data.active_subscribers.map_set)}"
    )

    Logger.info(
      "Capway active subscriber mapset: #{inspect(capway_subscriber_data.active_subscribers.map_set)}"
    )

    cancel_contracts =
      get_contracts_to_cancel(
        capway_subscriber_data.active_subscribers.data,
        trinity_subscriber_data.active_subscribers.map_set
      )

    update_contracts =
      get_contracts_to_update(
        capway_subscriber_data.active_subscribers.data,
        trinity_subscriber_data.active_subscribers.data
      )

    create_contracts =
      get_contracts_to_create(
        trinity_subscriber_data.active_subscribers.data,
        capway_subscriber_data.active_subscribers.map_set
      )

    suspend_accounts =
      get_accounts_to_suspend(
        capway_subscriber_data.inactive_subscribers.data,
        trinity_subscriber_data.active_subscribers.map_set
      )

    data = %{
      trinity: %{
        suspend_accounts: suspend_accounts
      },
      capway: %{
        cancel_contracts: cancel_contracts,
        update_contracts: update_contracts,
        create_contracts: create_contracts
      }
    }

    Logger.info("Comparison result data: #{inspect(data)}")
    Logger.info("Completed data comparison between Trinity and Capway subscribers")

    {:ok, data}
  end

  @doc """
   This function identifies Capway contracts that needs to be suspended in Trinity.
  """

  def get_accounts_to_suspend(capway_subscriber_data, trinity_subscriber_map_set) do
    Enum.reduce(capway_subscriber_data, [], fn capway_sub, acc ->
      if MapSet.member?(trinity_subscriber_map_set, capway_sub.trinity_subscriber_id) do
        # Subscriber should be suspended in trinity
        [
          %{
            national_id: capway_sub.national_id,
            trinity_subscriber_id: capway_sub.trinity_subscriber_id,
            reason: "Should be suspended in Trinity"
          }
          | acc
        ]
      else
        acc
      end
    end)
  end

  @doc """
   This function identifies Capway contracts that needs to be created.
   It will focus on checking for all active Trinity subscribers
   and see if they exist in Capway data, if not they will be marked for creation.
  """
  def get_contracts_to_create(trinity_subscriber_data, capway_subscriber_map_set) do
    Enum.reduce(trinity_subscriber_data, [], fn trinity_sub, acc ->
      if MapSet.member?(
           capway_subscriber_map_set,
           trinity_sub.trinity_subscriber_id
         ) do
        # Subscriber exists in both systems, no action needed
        acc
      else
        # Subscriber missing in Capway, mark for creation
        [
          %{
            national_id: trinity_sub.national_id,
            trinity_subscriber_id: trinity_sub.trinity_subscriber_id,
            reason: "Missing in Capway system"
          }
          | acc
        ]
      end
    end)
  end

  @doc """
  This function identifies Capway contracts that needs updating.
  It will focus on checking for all active Capway subscribers
  and compare it to trinity subscriber data, if the national_id is missing or is
  different than the one in Trinity, it will be marked for update.
  """
  def get_contracts_to_update(capway_subscriber_data, trinity_subscriber_data) do
    # First filter out the Capway subscribers that have no national_id
    Enum.reduce(capway_subscriber_data, [], fn capway_sub, acc ->
      # Start by checking if the subscriber exists in Trinity data
      # trinity_sub =
      #   Enum.find(trinity_subscriber_data, fn trinity_sub ->
      #     trinity_sub.trinity_subscriber_id == capway_sub.trinity_subscriber_id
      #   end)

      with trinity_sub <-
             Enum.find(trinity_subscriber_data, fn ts ->
               ts.trinity_subscriber_id == capway_sub.trinity_subscriber_id
             end),
           false <- trinity_sub == nil,
           false <- trinity_sub.national_id == capway_sub.national_id do
        # National IDs are different, mark for update
        [
          %{
            national_id: trinity_sub.national_id,
            trinity_subscriber_id: capway_sub.trinity_subscriber_id,
            reason: "National ID mismatch"
          }
          | acc
        ]
      else
        _ -> acc
      end
    end)
  end

  def get_contracts_to_cancel(capway_subscriber_data, trinity_subscriber_map_set) do
    Enum.reduce(capway_subscriber_data, [], fn capway_sub, acc ->
      if MapSet.member?(
           trinity_subscriber_map_set,
           capway_sub.trinity_subscriber_id
         ) do
        # Subscriber exists in both systems, no action needed
        acc
      else
        Logger.info(
          "Marking Capway subscriber #{capway_sub.trinity_subscriber_id} for cancellation"
        )

        # Subscriber missing in Trinity, mark for cancellation
        [
          %{
            national_id: capway_sub.national_id,
            trinity_subscriber_id: capway_sub.trinity_subscriber_id,
            reason: "Missing in Trinity system"
          }
          | acc
        ]
      end
    end)
  end
end
