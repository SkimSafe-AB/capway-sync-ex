defmodule CapwaySync.Ecto.TrinitySubscribers do
  import Ecto.Query

  alias CapwaySync.Repo
  alias CapwaySync.Models.Trinity.Subscriber

  def get_subscriber_by_pnr(pnr) do
    hashed_pnr = CapwaySync.Vault.Hashed.HMAC.hash(pnr)
    Repo.one(from(s in Subscriber, where: s.personal_number_hash == ^hashed_pnr))
  end

  # preload subscription
  def list_subscribers(include_relations \\ true) do
    query = from(s in Subscriber)

    if include_relations do
      query = Ecto.Query.preload(query, :wp_subscriptions)
    end

    Repo.all(query)
  end
end
