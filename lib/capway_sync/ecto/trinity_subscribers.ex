defmodule CapwaySync.Ecto.TrinitySubscribers do
  import Ecto.Query

  alias CapwaySync.TrinityRepo
  alias CapwaySync.Models.Trinity.Subscriber
  alias CapwaySync.Vault.Trinity.Hashed.HMAC

  def get_subscriber_by_pnr(pnr) do
    hashed_pnr = HMAC.hash(pnr)
    TrinityRepo.one(from(s in Subscriber, where: s.personal_number_hash == ^hashed_pnr))
  end

  # preload subscription
  def list_subscribers(include_relations \\ true) do
    Subscriber
    |> preload_subscription?(include_relations)
    |> TrinityRepo.all()
  end

  defp preload_subscription?(query, true), do: Ecto.Query.preload(query, :subscription)
  defp preload_subscription?(query, false), do: query
end
