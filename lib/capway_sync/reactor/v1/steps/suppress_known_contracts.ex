defmodule CapwaySync.Reactor.V1.Steps.SuppressKnownContracts do
  @moduledoc """
  Reactor step that removes `:capway_create_contract` action items for
  subscribers who — according to the `capway-contracts` DynamoDB table — still
  have a recently written **active** Capway contract.

  ## Why

  `CompareDataV2` can only see the Capway rows that today's SOAP fetch
  returned. If a row is missing from the fetch for any reason, the subscriber
  is flagged "Missing in Capway system" even though the contract exists. The
  `capway-contracts` table is written by every run from the same fetch, so a
  contract that was active there yesterday and simply did not come back today
  is a strong signal that the *fetch* is incomplete, not that the contract is
  gone. Suppressing the item costs nothing if the contract really was
  cancelled: an inactive contract is rewritten as `active: "false"` by the
  same run (this step depends on `store_capway_contracts` for ordering), and
  a row older than `max_age_days/0` is ignored.

  Suppressed items are logged at error level with the matching contract ref
  so an operator sees that the snapshot was incomplete.

  The step receives the `CompareDataV2` result under `:result` and returns
  the same structure with `actions.capway.create_contracts` filtered.
  """

  use Reactor.Step

  alias CapwaySync.Dynamodb.CapwayContractRepository
  alias CapwaySync.Models.CapwaySubscriber
  alias CapwaySync.Models.Dynamodb.ActionItem

  require Logger

  @max_age_days 3

  @typedoc "Looks up all stored contracts for a national id."
  @type lookup_fun :: (String.t() -> {:ok, [CapwaySubscriber.t()]} | {:error, term()})

  @doc "How recently a stored active contract must have been written to count."
  @spec max_age_days() :: pos_integer()
  def max_age_days, do: @max_age_days

  @impl true
  def run(%{result: result} = _args, _context, _options) do
    create_contracts = get_in(result, [:actions, :capway, :create_contracts]) || %{}

    {kept, suppressed} =
      filter_create_contracts(
        create_contracts,
        &CapwayContractRepository.get_contracts_by_national_id/1,
        DateTime.utc_now()
      )

    if suppressed != [] do
      Logger.error(
        "⚠️ Suppressed #{length(suppressed)} :capway_create_contract item(s) because the " <>
          "capway-contracts table still holds a recently written active contract for them. " <>
          "Today's Capway snapshot is probably incomplete."
      )
    end

    Logger.info(
      "SuppressKnownContracts: kept #{map_size(kept)}, suppressed #{length(suppressed)} create-contract items"
    )

    {:ok, put_in(result, [:actions, :capway, :create_contracts], kept)}
  end

  @doc """
  Splits `create_contracts` (a map of key → `ActionItem`) into the items to
  keep and the items to suppress.

  Returns `{kept_map, [{action_item, matching_contract}]}`. A lookup error
  keeps the item (fail open) and logs a warning.
  """
  @spec filter_create_contracts(map(), lookup_fun(), DateTime.t(), pos_integer()) ::
          {map(), [{ActionItem.t(), CapwaySubscriber.t()}]}
  def filter_create_contracts(create_contracts, lookup, now, max_age_days \\ @max_age_days) do
    {kept, suppressed} =
      Enum.reduce(create_contracts, {%{}, []}, fn {key, item}, {kept, suppressed} ->
        case known_active_contract(item, lookup, now, max_age_days) do
          nil ->
            {Map.put(kept, key, item), suppressed}

          contract ->
            Logger.error(
              "Suppressing :capway_create_contract for subscriber #{item.trinity_subscriber_id} " <>
                "(national id #{item.national_id}): contract #{contract.contract_ref_no} " <>
                "(customer #{contract.customer_id}) was active in capway-contracts at #{contract.updated_at}"
            )

            {kept, [{item, contract} | suppressed]}
        end
      end)

    {kept, Enum.reverse(suppressed)}
  end

  @doc """
  Returns the stored contract that proves the subscriber already has an
  active Capway contract, or `nil`.
  """
  @spec known_active_contract(ActionItem.t(), lookup_fun(), DateTime.t(), pos_integer()) ::
          CapwaySubscriber.t() | nil
  def known_active_contract(%{national_id: national_id}, _lookup, _now, _max_age_days)
      when national_id in [nil, ""] do
    nil
  end

  def known_active_contract(%{national_id: national_id}, lookup, now, max_age_days) do
    case lookup.(national_id) do
      {:ok, contracts} when is_list(contracts) ->
        Enum.find(contracts, &recently_active?(&1, now, max_age_days))

      {:error, reason} ->
        Logger.warning(
          "capway-contracts lookup failed for national id #{national_id}, keeping create item: #{inspect(reason)}"
        )

        nil
    end
  end

  @doc """
  True when the stored contract is active and was written within
  `max_age_days` of `now`.
  """
  @spec recently_active?(CapwaySubscriber.t(), DateTime.t(), pos_integer()) :: boolean()
  def recently_active?(
        %CapwaySubscriber{active: "true", updated_at: updated_at},
        %DateTime{} = now,
        max_age_days
      )
      when is_binary(updated_at) do
    case DateTime.from_iso8601(updated_at) do
      {:ok, written_at, _offset} -> DateTime.diff(now, written_at, :day) <= max_age_days
      _ -> false
    end
  end

  def recently_active?(_contract, _now, _max_age_days), do: false
end
