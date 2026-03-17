defmodule CapwaySync.Models.Trinity.Subscriber.Metadata do
  @moduledoc """
  Subscriber metadata schema
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t() :: %__MODULE__{}
  @derive Jason.Encoder
  # @primary_key false
  schema "subscriber_metadatas" do
    field(:key, :string)
    field(:value, :string)

    belongs_to(:subscriber, CapwaySync.Models.Trinity.Subscriber)

    timestamps()
  end

  @doc false
  def changeset(subscriber_metadata, attrs) do
    subscriber_metadata
    |> cast(attrs, [
      :key,
      :value,
      :subscriber_id
    ])
    |> validate_required([:key, :subscriber_id])
    |> unique_constraint(:key, name: :subscriber_metadata_subscriber_id_key_index)
  end
end
