defmodule CapwaySync.Models.Trinity.Subscriber do
  use Ecto.Schema
  import Ecto.Query

  @type t() :: %__MODULE__{}
  @derive Jason.Encoder
  schema "subscribers" do
    field(:personal_number_hash, CapwaySync.Vault.Trinity.Hashed.HMAC)
    field(:activated, :boolean, default: false)
    belongs_to(:subscription, CapwaySync.Models.Trinity.Subscription)
    timestamps()
  end
end
