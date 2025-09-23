defmodule CapwaySync.Models.Trinity.Subscriber do
  use Ecto.Schema
  import Ecto.Query

  @type t() :: %__MODULE__{}
  @derive Jason.Encoder
  schema "subscribers" do
    field(:personal_number_hash, CapwaySync.Vault.Hashed.HMAC)
    field(:activated, :boolean, default: false)
    has_many(:wp_subscriptions, CapwaySync.Models.Trinity.Subscription)
    timestamps()
  end
end
