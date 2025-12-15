defmodule CapwaySync.Reactor.V1.Steps.CompareDataV2 do
  alias ElixirSense.Log
  alias CapwaySync.Models.Dynamodb.ActionItem
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
      "Trinity active subscriber mapset: #{inspect(trinity_subscriber_data.active_subscribers)}"
    )

    Logger.info(
      "Capway active subscriber mapset: #{inspect(capway_subscriber_data.active_subscribers)}"
    )

    capway_cancel_contracts =
      get_contracts_to_cancel(
        capway_subscriber_data.active_subscribers,
        trinity_subscriber_data.active_subscribers
      )

    capway_update_contracts =
      get_contracts_to_update(
        capway_subscriber_data.active_subscribers,
        trinity_subscriber_data.active_subscribers
      )

    capway_create_contracts =
      get_contracts_to_create(
        trinity_subscriber_data.active_subscribers,
        capway_subscriber_data.active_subscribers
      )

    {trinity_suspend_accounts, trinity_cancel_accounts} =
      get_accounts_to_suspend_or_cancel(
        capway_subscriber_data.cancelled_subscribers,
        trinity_subscriber_data.active_subscribers
      )

    IO.inspect(map_size(capway_create_contracts), label: "Capway Create Contracts")

    data = %{
      trinity: %{
        cancel_accounts: trinity_cancel_accounts,
        suspend_accounts: trinity_suspend_accounts
      },
      capway: %{
        cancel_contracts: capway_cancel_contracts,
        update_contracts: capway_update_contracts,
        create_contracts: capway_create_contracts
      }
    }

    Logger.info("Comparison result data: #{inspect(data)}")
    Logger.info("Completed data comparison between Trinity and Capway subscribers")

    {:ok, data}
  end

  @doc """
  This function identifies Capway contracts that needs to be either suspended or cancelled in Trinity.
  The current rule is based on whetever the trinity subscription is locked in or not. Ie if it has a time based contract.
  If it is locked in, it should be suspended, otherwise cancelled.
  """

  def get_accounts_to_suspend_or_cancel(capway_subscriber_data, trinity_subscriber_data) do
    Enum.reduce(capway_subscriber_data, {%{}, %{}}, fn {_id, capway_sub},
                                                       {acc_suspend, acc_cancel} ->
      if Map.has_key?(trinity_subscriber_data, capway_sub.trinity_subscriber_id) do
        trinity_sub = Map.get(trinity_subscriber_data, capway_sub.trinity_subscriber_id)

        if trinity_sub.subscription_type == "locked" do
          item =
            ActionItem.create_action_item(:suspend, %{
              national_id: capway_sub.national_id,
              trinity_subscriber_id: capway_sub.trinity_subscriber_id,
              reason: "Should be suspended in Trinity due to locked subscription"
            })

          {Map.put(acc_suspend, capway_sub.trinity_subscriber_id, item), acc_cancel}
        else
          item =
            ActionItem.create_action_item(:trinity_cancel_subscription, %{
              national_id: capway_sub.national_id,
              trinity_subscriber_id: capway_sub.trinity_subscriber_id,
              reason: "Should be cancelled in Trinity due to inactive Capway status"
            })

          {acc_suspend, Map.put(acc_cancel, capway_sub.trinity_subscriber_id, item)}
        end
      else
        {acc_suspend, acc_cancel}
      end
    end)
  end

  @doc """
  This function identifies Capway contracts that needs to be created.
  It will focus on checking for all active Trinity subscribers
  and see if they exist in Capway data, if not they will be marked for creation.
  """
  def get_contracts_to_create(trinity_subscriber_data, capway_subscriber_data) do
    Enum.reduce(trinity_subscriber_data, %{}, fn {trinity_subscriber_id, trinity_sub}, acc ->
      Logger.info("Checking Trinity subscriber ID #{trinity_subscriber_id} for creation")
      Logger.info("trinity sub", inspect(trinity_sub))

      if Map.has_key?(
           capway_subscriber_data,
           trinity_subscriber_id
         ) do
        # Subscriber exists in both systems, no action needed
        acc
      else
        if(trinity_sub.payment_method == "capway") do
          # Subscriber missing in Capway, mark for creation
          item =
            ActionItem.create_action_item(:capway_create_contract, %{
              national_id: trinity_sub.national_id,
              trinity_subscriber_id: trinity_subscriber_id,
              reason: "Missing in Capway system"
            })

          Map.put(acc, trinity_sub.trinity_subscriber_id, item)
        else
          acc
        end
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
    Enum.reduce(capway_subscriber_data, %{}, fn {_id, capway_sub}, acc ->
      with true <- Map.has_key?(trinity_subscriber_data, capway_sub.trinity_subscriber_id),
           trinity_sub <-
             Map.get(
               trinity_subscriber_data,
               capway_sub.trinity_subscriber_id
             ),
           false <- trinity_sub == nil,
           false <- trinity_sub.national_id == capway_sub.national_id do
        # National IDs are different, mark for update
        item =
          ActionItem.create_action_item(:capway_update_contract, %{
            national_id: trinity_sub.national_id,
            trinity_subscriber_id: capway_sub.trinity_subscriber_id,
            reason: "National ID mismatch"
          })

        Map.put(acc, capway_sub.trinity_subscriber_id, item)
      else
        _ -> acc
      end
    end)
  end

  def get_contracts_to_cancel(capway_subscriber_data, trinity_subscriber_data) do
    Enum.reduce(capway_subscriber_data, %{}, fn {trinity_subscriber_id, capway_sub}, acc ->
      if Map.has_key?(
           trinity_subscriber_data,
           trinity_subscriber_id
         ) do
        # Subscriber exists in both systems, no action needed
        acc
      else
        # Logger.info("Marking Capway subscriber #{trinity_subscriber_id} for cancellation")

        # Subscriber missing in Trinity, mark for cancellation
        item =
          ActionItem.create_action_item(:capway_cancel_contract, %{
            national_id: capway_sub.national_id,
            trinity_subscriber_id: trinity_subscriber_id,
            reason: "Missing in Trinity system"
          })

        Map.put(acc, trinity_subscriber_id, item)
      end
    end)
  end
end
