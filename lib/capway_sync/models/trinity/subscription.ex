defmodule CapwaySync.Models.Trinity.Subscription do
  use Ecto.Schema
  import Ecto.Query

  @type t() :: %__MODULE__{}
  @derive Jason.Encoder
  schema "subscriptions" do
    field(:end_date, :naive_datetime)
    field(:payment_method, :string)
    field(:requested_cancellation_date, :naive_datetime)
    field(:requested_cancellation, :boolean, default: false)
    has_many(:subscribers, CapwaySync.Models.Trinity.Subscriber)
  end
end
