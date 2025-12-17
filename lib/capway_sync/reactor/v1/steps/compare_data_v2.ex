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
      "Trinity locked subscribers: #{inspect(trinity_subscriber_data.locked_subscribers)}"
    )

    Logger.info("Capway active subscriber mapset: #{inspect(capway_subscriber_data.map_sets)}")

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
        capway_subscriber_data.map_sets
      )

    {trinity_suspend_accounts, trinity_cancel_accounts} =
      get_accounts_to_suspend_or_cancel(
        capway_subscriber_data.above_collector_threshold,
        trinity_subscriber_data.active_subscribers,
        trinity_subscriber_data.map_sets
      )

    data = %{
      source: %{
        trinity: trinity_subscriber_data,
        capway: capway_subscriber_data
      },
      actions: %{
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

  def get_accounts_to_suspend_or_cancel(
        capway_subscriber_data,
        trinity_subscriber_data,
        trinity_map_set
      ) do
    Enum.reduce(capway_subscriber_data, {%{}, %{}}, fn {_id, capway_sub},
                                                       {acc_suspend, acc_cancel} ->
      if Map.has_key?(trinity_subscriber_data, capway_sub.trinity_subscriber_id) or
           MapSet.member?(
             trinity_map_set.active_national_ids,
             capway_sub.national_id
           ) do
        trinity_sub =
          Map.get(trinity_subscriber_data, capway_sub.trinity_subscriber_id)
          |> ensure_map_get(capway_sub.national_id, capway_subscriber_data)

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

  defp ensure_map_get(data, key, capway_subs) when is_nil(data) do
    # We need to fetch the data with the national_id instead
    {_id, cw_sub} =
      Enum.find(capway_subs, fn {_id, sub} ->
        sub.national_id == key
      end)

    cw_sub
  end

  defp ensure_map_get(data, _key, _capway_subs), do: data

  @doc """
  This function identifies Capway contracts that needs to be created.
  It will focus on checking for all active Trinity subscribers
  and see if they exist in Capway data, if not they will be marked for creation.
  Currently we check against both national_id and trinity_subscriber_id to determine existence.
  """
  def get_contracts_to_create(trinity_subscriber_data, capway_map_sets) do
    Enum.filter(trinity_subscriber_data, fn {_id, trinity_sub} ->
      trinity_sub.payment_method == "capway"
    end)
    |> Enum.reject(fn {_id, trinity_sub} ->
      MapSet.member?(
        capway_map_sets.active_national_ids,
        trinity_sub.national_id
      ) or
        MapSet.member?(
          capway_map_sets.active_trinity_ids,
          trinity_sub.trinity_subscriber_id
        )
    end)
    |> Map.new(fn {_id, sub} ->
      # Subscriber missing in Capway, mark for creation
      item =
        ActionItem.create_action_item(:capway_create_contract, %{
          national_id: sub.national_id,
          trinity_subscriber_id: sub.trinity_subscriber_id,
          reason: "Missing in Capway system"
        })

      {sub.trinity_subscriber_id, item}
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
           true <- check_for_missing_attrs(capway_sub, trinity_sub) do
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

  defp check_for_missing_attrs(capway_sub, trinity_sub) do
    capway_sub.national_id == nil or
      capway_sub.national_id != trinity_sub.national_id or
      capway_sub.trinity_subscriber_id == nil or
      capway_sub.trinity_subscriber_id != trinity_sub.trinity_subscriber_id
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
