defmodule CapwaySync.Models.Dynamodb.ActionItem do
  @type action_type ::
          :trinity_cancel_subscription
          | :trinity_suspend_subscription
          | :trinity_unsuspend_subscription
          | :capway_create_contract
          | :capway_cancel_contract
          | :capway_update_contract

  @type t :: %__MODULE__{
          id: String.t() | nil,
          trinity_subscriber_id: Integer.t() | nil,
          national_id: String.t() | nil,
          created_at: String.t(),
          timestamp: non_neg_integer(),
          action: String.t(),
          status: :pending | :completed | :failed,
          comment: String.t() | nil
        }

  @derive Jason.Encoder
  @derive ExAws.Dynamo.Encodable
  defstruct id: nil,
            trinity_subscriber_id: nil,
            national_id: nil,
            created_at: nil,
            timestamp: 0,
            action: nil,
            status: :pending,
            comment: nil

  @spec create_action_item(atom(), map()) :: t()
  def create_action_item(action, data) do
    %__MODULE__{
      id: UUID.uuid4(),
      trinity_subscriber_id: Map.get(data, :trinity_subscriber_id, nil),
      national_id: Map.get(data, :national_id, nil),
      created_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      timestamp: DateTime.utc_now() |> DateTime.to_unix(),
      action: action,
      status: :pending,
      comment: Map.get(data, :reason, "")
    }
  end
end
