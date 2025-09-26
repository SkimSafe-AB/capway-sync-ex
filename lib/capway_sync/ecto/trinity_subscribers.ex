defmodule CapwaySync.Ecto.TrinitySubscribers do
  import Ecto.Query

  alias CapwaySync.TrinityRepo
  alias CapwaySync.Models.Trinity.Subscriber
  alias CapwaySync.Vault.Trinity.Hashed.HMAC

  def get_subscriber_by_pnr(pnr) do
    hashed_pnr = HMAC.hash(pnr)
    TrinityRepo.one(from(s in Subscriber, where: s.personal_number_hash == ^hashed_pnr))
  end

  # get all subscribers with subscription and its payment_method == capway
  # the payment_method is stored in the subscription table
  def list_subscribers(preload_subscription \\ false) do
    Subscriber
    |> join(:inner, [s], sub in assoc(s, :subscription))
    |> where([s, sub], sub.payment_method == "capway")
    |> preload_subscription?(preload_subscription)
    |> TrinityRepo.all()
  end

  defp preload_subscription?(query, true), do: Ecto.Query.preload(query, :subscription)
  defp preload_subscription?(query, false), do: query
end
