defmodule CapwaySync.Models.Trinity.Subscription do
  use Ecto.Schema
  import Ecto.Changeset

  @statuses [
    active: "active",
    on_hold: "on-hold",
    cancelled: "cancelled",
    pending_cancel: "pending-cancel",
    pending: "pending",
    expired: "expired",
    inactive: "inactive",
    suspended: "suspended",
    paused: "paused"
  ]

  @subscription_types [
    regular: "regular",
    locked: "locked",
    unlocked: "unlocked",
    trial: "trial",
    securio: "securio",
    sinfrid: "sinfrid"
  ]

  @type t() :: %__MODULE__{}
  @derive Jason.Encoder
  schema "subscriptions" do
    field(:end_date, :naive_datetime)
    field(:payment_method, :string)
    field(:requested_cancellation_date, :naive_datetime)
    field(:requested_cancellation, :boolean, default: false)
    field(:status, Ecto.Enum, values: @statuses)
    field(:subscription_type, Ecto.Enum, values: @subscription_types)
    has_many(:subscribers, CapwaySync.Models.Trinity.Subscriber)
    timestamps()
  end

  def changeset(subscription, attrs) do
    subscription
    |> cast(attrs, [
      :end_date,
      :payment_method,
      :requested_cancellation_date,
      :requested_cancellation,
      :status,
      :subscription_type
    ])
    |> validate_required([:payment_method, :status])
  end
end
