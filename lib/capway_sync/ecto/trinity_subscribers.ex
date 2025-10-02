defmodule CapwaySync.Ecto.TrinitySubscribers do
  import Ecto.Query

  alias CapwaySync.TrinityRepo
  alias CapwaySync.Models.Trinity.Subscriber
  alias CapwaySync.Vault.Trinity.Hashed.HMAC
  require Logger

  def get_subscriber_by_pnr(pnr) do
    hashed_pnr = HMAC.hash(pnr)
    query = from(s in Subscriber, where: s.personal_number_hash == ^hashed_pnr)
    execute_with_retry(fn -> TrinityRepo.one(query) end, 3)
  end

  # get all subscribers with subscription and its payment_method == capway
  # the payment_method is stored in the subscription table
  def list_subscribers(preload_subscription \\ false, payment_method \\ nil) do
    query =
      Subscriber
      |> join(:inner, [s], sub in assoc(s, :subscription))
      # |> where([s, sub], sub.payment_method == "capway")
      |> filter_by_payment_method?(payment_method)
      |> preload_subscription?(preload_subscription)

    execute_with_retry(fn -> TrinityRepo.all(query) end, 3)
  end

  defp preload_subscription?(query, true), do: Ecto.Query.preload(query, :subscription)
  defp preload_subscription?(query, false), do: query

  defp filter_by_payment_method?(query, nil), do: query

  defp filter_by_payment_method?(query, payment_method),
    do: where(query, [s, sub], sub.payment_method == ^payment_method)

  defp execute_with_retry(query_fn, retries_left) do
    try do
      query_fn.()
    rescue
      error ->
        case error do
          %DBConnection.ConnectionError{} when retries_left > 0 ->
            Logger.warning(
              "Trinity database connection error, retrying... (#{retries_left} retries left) - #{inspect(error)}"
            )

            Process.sleep(1000 * (4 - retries_left))
            execute_with_retry(query_fn, retries_left - 1)

          %Postgrex.Error{postgres: %{code: code}}
          when retries_left > 0 and code in ["08000", "08003", "08006", "57P01"] ->
            Logger.warning(
              "Trinity database connection lost, retrying... (#{retries_left} retries left) - #{inspect(error)}"
            )

            Process.sleep(1500 * (4 - retries_left))
            execute_with_retry(query_fn, retries_left - 1)

          _ ->
            Logger.error("Trinity database query failed: #{inspect(error)}")
            reraise error, __STACKTRACE__
        end
    end
  end
end
