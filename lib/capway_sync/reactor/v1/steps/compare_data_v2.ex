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

    subscriber_to_subscription_ids =
      trinity_subscriber_data.map_sets.subscriber_to_subscription_ids

    capway_cancel_contracts =
      get_contracts_to_cancel(
        capway_subscriber_data.active_subscribers,
        trinity_subscriber_data.active_subscribers,
        subscriber_to_subscription_ids,
        trinity_subscriber_data.map_sets.all_national_ids,
        trinity_subscriber_data.map_sets.all_subscriber_ids,
        trinity_subscriber_data.map_sets.recently_cancelled_subscriber_ids,
        trinity_subscriber_data.map_sets.recently_cancelled_national_ids
      )

    capway_update_customers =
      get_customers_to_update(
        capway_subscriber_data.active_subscribers,
        trinity_subscriber_data.active_subscribers,
        subscriber_to_subscription_ids
      )
      |> Map.drop(Map.keys(capway_cancel_contracts))

    capway_update_contracts =
      get_contracts_to_update(
        capway_subscriber_data.active_subscribers,
        trinity_subscriber_data.active_subscribers,
        subscriber_to_subscription_ids
      )
      |> Map.drop(Map.keys(capway_cancel_contracts))
      |> Map.drop(Map.keys(capway_update_customers))

    capway_create_contracts =
      get_contracts_to_create(
        trinity_subscriber_data.active_subscribers,
        capway_subscriber_data.map_sets,
        capway_subscriber_data.associated_subscribers
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
          update_customers: capway_update_customers,
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
  Identifies Capway contracts that need to be created.

  Checks all active Trinity subscribers against Capway data — if not found among
  active Capway contracts, marks them for creation. When an inactive Capway contract
  exists for the subscriber (matched by national_id or trinity_subscriber_id), the
  action item is enriched with the existing Capway references (customer_id,
  contract_guid, contract_ref).
  """
  def get_contracts_to_create(
        trinity_subscriber_data,
        capway_map_sets,
        capway_all_subscribers \\ %{}
      ) do
    for {_id, sub} <- trinity_subscriber_data,
        sub.payment_method == "capway",
        not MapSet.member?(capway_map_sets.active_trinity_ids, sub.trinity_subscriber_id),
        not MapSet.member?(capway_map_sets.active_national_ids, sub.national_id),
        older_than_yesterday?(sub),
        into: %{} do
      reason = "Missing in Capway system"

      Logger.info(
        "Subscriber #{sub.trinity_subscriber_id} is missing in Capway, marking for contract creation"
      )

      enriched_sub = enrich_with_capway_data(sub, capway_all_subscribers)

      {sub.trinity_subscriber_id, build_action_item(:capway_create_contract, enriched_sub, reason)}
    end
  end

  @doc """
  Identifies Capway contracts where the national ID differs from Trinity.

  When the national ID on the Capway side does not match the Trinity national ID,
  the customer record in Capway needs to be updated. These are tagged as
  `capway_update_customer` action items.
  """
  def get_customers_to_update(
        capway_subscriber_data,
        trinity_subscriber_data,
        subscriber_to_subscription_ids \\ %{}
      ) do
    for {contract_ref, capway_sub} <- capway_subscriber_data,
        Map.has_key?(trinity_subscriber_data, capway_sub.trinity_subscriber_id),
        trinity_sub = Map.get(trinity_subscriber_data, capway_sub.trinity_subscriber_id),
        has_national_id_mismatch?(capway_sub, trinity_sub),
        (capway_sub.collection || 0) < 2,
        into: %{} do
      reason = "National ID mismatch"

      enriched_sub = enrich_subscription_id(capway_sub, subscriber_to_subscription_ids)
      {contract_ref, build_action_item(:capway_update_customer, enriched_sub, reason)}
    end
  end

  @doc """
  Identifies Capway contracts where the subscriber ID is missing or mismatched,
  but the national ID matches.

  These are tagged as `capway_update_contract` action items.
  """
  def get_contracts_to_update(
        capway_subscriber_data,
        trinity_subscriber_data,
        subscriber_to_subscription_ids \\ %{}
      ) do
    for {contract_ref, capway_sub} <- capway_subscriber_data,
        Map.has_key?(trinity_subscriber_data, capway_sub.trinity_subscriber_id),
        trinity_sub = Map.get(trinity_subscriber_data, capway_sub.trinity_subscriber_id),
        has_subscriber_id_mismatch_only?(capway_sub, trinity_sub),
        (capway_sub.collection || 0) < 2,
        into: %{} do
      reason = "Subscriber ID mismatch"

      enriched_sub = enrich_subscription_id(capway_sub, subscriber_to_subscription_ids)
      {contract_ref, build_action_item(:capway_update_contract, enriched_sub, reason)}
    end
  end

  defp has_national_id_mismatch?(capway_sub, trinity_sub) do
    capway_sub.national_id != trinity_sub.national_id and
      valid_national_id?(trinity_sub.national_id)
  end

  defp has_subscriber_id_mismatch_only?(capway_sub, trinity_sub) do
    capway_sub.national_id == trinity_sub.national_id and
      (capway_sub.trinity_subscriber_id == nil or
         capway_sub.trinity_subscriber_id != trinity_sub.trinity_subscriber_id) and
      valid_national_id?(trinity_sub.national_id)
  end

  defp valid_national_id?(nil), do: false

  defp valid_national_id?(national_id) do
    case Application.get_env(:capway_sync, :market) do
      :se -> Personnummer.valid?(national_id)
      _ -> true
    end
  end

  @doc """
  Identifies Capway contracts with no matching Trinity subscriber.

  Checks `trinity_subscriber_id`, `national_id`, and all known subscriber IDs
  (including pending/not-yet-activated) before marking for cancellation.
  Also excludes contracts where the Trinity subscriber has a recent
  `capway_cancelled_at` (within 2 days), indicating cancellation was already processed.
  """
  def get_contracts_to_cancel(
        capway_subscriber_data,
        trinity_subscriber_data,
        subscriber_to_subscription_ids \\ %{},
        trinity_all_national_ids \\ MapSet.new(),
        trinity_all_subscriber_ids \\ MapSet.new(),
        recently_cancelled_subscriber_ids \\ MapSet.new(),
        recently_cancelled_national_ids \\ MapSet.new()
      ) do
    for {contract_ref, capway_sub} <- capway_subscriber_data,
        not Map.has_key?(trinity_subscriber_data, capway_sub.trinity_subscriber_id),
        not MapSet.member?(trinity_all_national_ids, capway_sub.national_id),
        not MapSet.member?(trinity_all_subscriber_ids, capway_sub.trinity_subscriber_id),
        not MapSet.member?(recently_cancelled_subscriber_ids, capway_sub.trinity_subscriber_id),
        not MapSet.member?(recently_cancelled_national_ids, capway_sub.national_id),
        into: %{} do
      reason = "No matching Trinity account found"

      enriched_sub = enrich_subscription_id(capway_sub, subscriber_to_subscription_ids)
      {contract_ref, build_action_item(:capway_cancel_contract, enriched_sub, reason)}
    end
  end

  defp enrich_with_capway_data(sub, capway_all_subscribers) when map_size(capway_all_subscribers) == 0 do
    sub
  end

  defp enrich_with_capway_data(sub, capway_all_subscribers) do
    case find_capway_match(sub, capway_all_subscribers) do
      nil ->
        sub

      capway_sub ->
        %{
          sub
          | capway_customer_id: capway_sub.capway_customer_id,
            capway_contract_guid: capway_sub.capway_contract_guid,
            capway_contract_ref: capway_sub.capway_contract_ref
        }
    end
  end

  defp find_capway_match(sub, capway_all_subscribers) do
    Enum.find_value(capway_all_subscribers, fn {_ref, capway_sub} ->
      if capway_sub.national_id == sub.national_id or
           (capway_sub.trinity_subscriber_id != nil and
              capway_sub.trinity_subscriber_id == sub.trinity_subscriber_id) do
        capway_sub
      end
    end)
  end

  defp enrich_subscription_id(capway_sub, subscriber_to_subscription_ids) do
    case Map.get(subscriber_to_subscription_ids, capway_sub.trinity_subscriber_id) do
      nil -> capway_sub
      subscription_id -> %{capway_sub | trinity_subscription_id: subscription_id}
    end
  end

  defp build_action_item(action, sub, reason) do
    ActionItem.create_action_item(action, %{
      national_id: sub.national_id,
      trinity_subscriber_id: sub.trinity_subscriber_id,
      trinity_subscription_id: sub.trinity_subscription_id,
      capway_customer_id: sub.capway_customer_id,
      capway_contract_guid: sub.capway_contract_guid,
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
