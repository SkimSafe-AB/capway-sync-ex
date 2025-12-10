defmodule CapwaySync.Models.Trinity.Subscriber do
  use Ecto.Schema
  import Ecto.Changeset

  @type t() :: %__MODULE__{}
  @derive Jason.Encoder
  schema "subscribers" do
    field(:personal_number_hash, CapwaySync.Vault.Trinity.Hashed.HMAC)
    field(:personal_number, CapwaySync.Vault.Trinity.Encrypted.Binary)
    field(:activated, :boolean, default: false)
    belongs_to(:subscription, CapwaySync.Models.Trinity.Subscription)
    timestamps()
  end

  def changeset(subscriber, attrs) do
    subscriber
    |> cast(attrs, [:personal_number, :activated, :subscription_id])
    |> validate_required([:personal_number, :subscription_id])
    |> put_personal_number_hash()
  end

  defp put_personal_number_hash(changeset) do
    case get_change(changeset, :personal_number) do
      nil ->
        changeset

      personal_number ->
        put_change(
          changeset,
          :personal_number_hash,
          CapwaySync.Vault.Trinity.Hashed.HMAC.hash(personal_number)
        )
    end
  end
end
