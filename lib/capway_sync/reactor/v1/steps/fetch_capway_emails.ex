defmodule CapwaySync.Reactor.V1.Steps.FetchCapwayEmails do
  @moduledoc """
  Reactor step that backfills the Capway-side email on each active Capway
  canonical entry by calling the payment processor REST API one-by-one.

  Why this exists: the Capway SOAP response intentionally drops the email
  column, so the canonical Capway entries arrive at this step with `email: nil`.
  The downstream `CompareDataV2` step needs both Trinity-side and Capway-side
  emails to detect drift and emit `:capway_update_customer` action items.

  The step:
    * walks `data.capway.active_subscribers` (a map keyed by contract_ref)
    * skips entries with no `capway_customer_id`
    * skips entries whose Trinity counterpart has `capway_sync_excluded: true`
      (looked up by `national_id` against `data.trinity.active_subscribers`)
    * fetches each email concurrently via `Task.async_stream/3`
    * tolerates `:not_found` and any other client error by leaving `email: nil`
      (the comparison step treats nil as "unknown" → no action)

  Returns the input data shape unchanged except that
  `data.capway.active_subscribers` has emails populated where they were fetched
  successfully.
  """

  use Reactor.Step
  require Logger

  @default_max_concurrency 10
  @default_timeout 30_000

  @impl Reactor.Step
  def run(args, _context, _options) do
    capway = Map.get(args.data, :capway, %{})
    trinity = Map.get(args.data, :trinity, %{})

    active_capway = Map.get(capway, :active_subscribers, %{})
    excluded_national_ids = collect_excluded_national_ids(trinity)

    Logger.info(
      "Fetching Capway emails for #{map_size(active_capway)} active capway subscribers " <>
        "(excluded: #{MapSet.size(excluded_national_ids)})"
    )

    enriched =
      active_capway
      |> Enum.filter(fn {_ref, sub} -> fetchable?(sub, excluded_national_ids) end)
      |> Task.async_stream(
        fn {ref, sub} -> {ref, fetch_email(sub)} end,
        max_concurrency: max_concurrency(),
        timeout: @default_timeout,
        on_timeout: :kill_task,
        ordered: false
      )
      |> Enum.reduce(active_capway, fn
        {:ok, {_ref, nil}}, acc ->
          acc

        {:ok, {ref, email}}, acc ->
          Map.update!(acc, ref, fn sub -> %{sub | email: email} end)

        {:exit, reason}, acc ->
          Logger.error("Capway email fetch task exited: #{inspect(reason)}")
          acc
      end)

    updated_capway = Map.put(capway, :active_subscribers, enriched)

    {:ok, %{capway: updated_capway, trinity: trinity}}
  end

  @impl Reactor.Step
  def compensate(_error, _arguments, _context, _options), do: :retry

  @impl Reactor.Step
  def undo(_result, _arguments, _context, _options), do: :ok

  defp fetchable?(%{capway_customer_id: nil}, _excluded), do: false

  defp fetchable?(%{capway_customer_id: customer_id, national_id: national_id}, excluded)
       when is_binary(customer_id) do
    not MapSet.member?(excluded, national_id)
  end

  defp fetchable?(_sub, _excluded), do: false

  defp fetch_email(%{capway_customer_id: customer_id} = sub) do
    case client().get_capway_customer_by_id(customer_id) do
      {:ok, body} ->
        extract_email(body)

      {:error, :not_found} ->
        Logger.debug("Capway customer #{customer_id} not found in payment processor")
        nil

      {:error, reason} ->
        Logger.warning(
          "Could not fetch capway customer #{customer_id} (national_id=#{sub.national_id}): " <>
            inspect(reason)
        )

        nil
    end
  end

  defp extract_email(%{"email" => email}) when is_binary(email) and email != "", do: email
  defp extract_email(%{"Email" => email}) when is_binary(email) and email != "", do: email
  defp extract_email(_), do: nil

  defp collect_excluded_national_ids(trinity) do
    trinity
    |> Map.get(:active_subscribers, %{})
    |> Enum.reduce(MapSet.new(), fn {_id, sub}, acc ->
      if Map.get(sub, :capway_sync_excluded, false) do
        MapSet.put(acc, sub.national_id)
      else
        acc
      end
    end)
  end

  defp client do
    Application.get_env(
      :capway_sync,
      :payment_processor_client,
      CapwaySync.Clients.PaymentProcessor.Client
    )
  end

  defp max_concurrency do
    case System.get_env("CAPWAY_EMAIL_FETCH_CONCURRENCY") do
      nil ->
        @default_max_concurrency

      value ->
        case Integer.parse(value) do
          {n, _} when n > 0 -> n
          _ -> @default_max_concurrency
        end
    end
  end
end
