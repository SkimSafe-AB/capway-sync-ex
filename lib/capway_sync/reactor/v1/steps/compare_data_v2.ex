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
      |> exclude_existing_by_national_id(capway_subscriber_data.map_sets)

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
  Identifies Capway contracts that need to be either suspended or cancelled in Trinity.

  Capway data is keyed by `capway_contract_ref`, so each contract is evaluated independently.
  Two active contracts for the same customer produce two separate action items.

  The rule is based on whether the Trinity subscription is locked or not:
  - Locked → suspend
  - Not locked → cancel (unless pending_cancel, non-capway payment, or last invoice paid)
  """
  def get_accounts_to_suspend_or_cancel(
        capway_subscriber_data,
        trinity_subscriber_data,
        trinity_map_set
      ) do
    Enum.reduce(capway_subscriber_data, {%{}, %{}}, fn {contract_ref, capway_sub},
                                                       {suspend, cancel} ->
      with true <- Map.has_key?(trinity_subscriber_data, capway_sub.trinity_subscriber_id),
           true <- confirm_relationship(trinity_subscriber_data, trinity_map_set, capway_sub),
           trinity_sub when not is_nil(trinity_sub) <-
             Map.get(trinity_subscriber_data, capway_sub.trinity_subscriber_id)
             |> ensure_map_get(capway_sub.national_id, capway_subscriber_data),
           true <- trinity_sub.trinity_status != :suspended,
           true <- trinity_sub.trinity_status != :cancelled do
        suspend_or_cancel_action(contract_ref, capway_sub, trinity_sub, suspend, cancel)
      else
        _ -> {suspend, cancel}
      end
    end)
  end

  defp confirm_relationship(t_sub_data, t_map_sets, c_sub) do
    Map.has_key?(t_sub_data, c_sub.trinity_subscriber_id) or
      MapSet.member?(t_map_sets.active_national_ids, c_sub.national_id)
  end

  defp suspend_or_cancel_action(contract_ref, capway_sub, trinity_sub, suspend_acc, cancel_acc) do
    if trinity_sub.subscription_type == :locked do
      reason = "Should be suspended in Trinity due to locked subscription"
      item = build_action_item(:suspend, capway_sub, reason)

      {Map.put(suspend_acc, contract_ref, item), cancel_acc}
    else
      if trinity_sub.trinity_status == :pending_cancel or
           trinity_sub.payment_method != "capway" or
           capway_sub.last_invoice_status == "Paid" do
        {suspend_acc, cancel_acc}
      else
        reason = "Should be cancelled in Trinity due to inactive Capway status"
        item = build_action_item(:trinity_cancel_subscription, capway_sub, reason)

        {suspend_acc, Map.put(cancel_acc, contract_ref, item)}
      end
    end
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
    for {_id, sub} <- trinity_subscriber_data,
        sub.payment_method == "capway",
        not MapSet.member?(capway_map_sets.active_trinity_ids, sub.trinity_subscriber_id),
        older_than_yesterday?(sub),
        into: %{} do
      reason = "Missing in Capway system"

      Logger.info(
        "Subscriber #{sub.trinity_subscriber_id} is missing in Capway, marking for contract creation"
      )

      found = MapSet.member?(capway_map_sets.active_trinity_ids, sub.trinity_subscriber_id)

      Logger.info(
        "Check if subscriber #{sub.trinity_subscriber_id} exists in Capway active Trinity IDs: #{found}"
      )

      {sub.trinity_subscriber_id, build_action_item(:capway_create_contract, sub, reason)}
    end
  end

  @doc """
  Excludes subscribers from contract creation if their `national_id` already
  exists in Capway's active subscribers. This catches cases where a subscriber
  exists in Capway without a `trinity_subscriber_id` (e.g. sinfrid customers).
  """
  @spec exclude_existing_by_national_id(%{integer() => map()}, %{active_national_ids: MapSet.t()}) ::
          %{integer() => map()}
  def exclude_existing_by_national_id(create_contracts, capway_map_sets) do
    Map.reject(create_contracts, fn {_id, action_item} ->
      MapSet.member?(capway_map_sets.active_national_ids, action_item.national_id)
    end)
  end

  @doc """
  This function identifies Capway contracts that needs updating.
  It will focus on checking for all active Capway subscribers
  and compare it to trinity subscriber data, if the national_id is missing or is
  different than the one in Trinity, it will be marked for update.
  """
  def get_contracts_to_update(capway_subscriber_data, trinity_subscriber_data) do
    for {contract_ref, capway_sub} <- capway_subscriber_data,
        Map.has_key?(trinity_subscriber_data, capway_sub.trinity_subscriber_id),
        trinity_sub = Map.get(trinity_subscriber_data, capway_sub.trinity_subscriber_id),
        check_for_missing_attrs(capway_sub, trinity_sub),
        into: %{} do
      reason = "National ID mismatch"

      {contract_ref, build_action_item(:capway_update_contract, capway_sub, reason)}
    end
  end

  defp check_for_missing_attrs(capway_sub, trinity_sub) do
    has_mismatch =
      capway_sub.national_id != trinity_sub.national_id or
        capway_sub.trinity_subscriber_id == nil or
        capway_sub.trinity_subscriber_id != trinity_sub.trinity_subscriber_id

    has_mismatch and valid_national_id?(trinity_sub.national_id)
  end

  defp valid_national_id?(nil), do: false

  defp valid_national_id?(national_id) do
    case Application.get_env(:capway_sync, :market) do
      :se -> Personnummer.valid?(national_id)
      _ -> true
    end
  end

  @doc """
  Identifies Capway contracts with no matching Trinity subscriber by `trinity_subscriber_id`.

  Contracts that can be matched are handled by the suspend/cancel logic instead.
  """
  def get_contracts_to_cancel(capway_subscriber_data, trinity_subscriber_data) do
    for {contract_ref, capway_sub} <- capway_subscriber_data,
        not Map.has_key?(trinity_subscriber_data, capway_sub.trinity_subscriber_id),
        into: %{} do
      reason = "No matching Trinity account found"

      {contract_ref, build_action_item(:capway_cancel_contract, capway_sub, reason)}
    end
  end

  defp build_action_item(action, sub, reason) do
    ActionItem.create_action_item(action, %{
      national_id: sub.national_id,
      trinity_subscriber_id: sub.trinity_subscriber_id,
      capway_contract_ref: sub.capway_contract_ref,
      reason: reason
    })
  end

  defp older_than_yesterday?(nil), do: false
  defp older_than_yesterday?(%{trinity_subscription_updated_at: nil} = _sub), do: false

  defp older_than_yesterday?(%{trinity_subscription_updated_at: dt} = _sub) do
    dt
    |> Timex.to_datetime("Etc/UTC")
    |> Timex.before?(Timex.shift(Timex.now("Etc/UTC"), days: -1))
  end
end
