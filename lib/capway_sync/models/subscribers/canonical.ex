defmodule CapwaySync.Models.Subscribers.Canonical do
  @moduledoc """
  Canonical representation of a subscriber for cross-system comparison.

  This struct provides a unified format for comparing subscribers from different
  systems (Trinity, Capway) without coupling domain-specific data structures.
  Both Trinity and Capway data are converted to this canonical format for
  consistent comparison logic.

  ## Fields

  - `national_id`: Unique identifier (personal number) for comparison
  - `trinity_subscriber_id`: Original Trinity subscriber ID (if from Trinity)
  - `capway_contract_ref`: Original Capway customer reference (if from Capway)
  - `payment_method`: Payment method (Trinity-specific, nil for Capway data)
  - `active`: Whether the subscription/contract is active
  - `end_date`: Subscription/contract end date
  - `origin`: Source system (:trinity or :capway)
  - `status`: Original subscription status from Trinity (nil for Capway data)
  - `subscription_type`: Subscription type from Trinity (e.g., "locked", nil for Capway data)
  - `capway_active_status`: Capway active status (enriched during comparison, nil if not enriched)

  ## Usage

      # Convert Trinity subscriber to canonical format
      canonical = Subscribers.Canonical.from_trinity(trinity_subscriber)

      # Convert Capway subscriber to canonical format
      canonical = Subscribers.Canonical.from_capway(capway_subscriber)
  """

  @type t :: %__MODULE__{
          # Ids, references
          national_id: String.t(),
          trinity_subscriber_id: integer() | nil,
          trinity_subscription_id: integer() | nil,
          capway_contract_ref: String.t(),
          # Subscription details
          end_date: String.t() | nil,
          origin: :trinity | :capway,
          # Trinity specific data
          payment_method: String.t() | nil,
          subscription_type: String.t() | nil,
          trinity_status: atom() | nil,
          # Capway specific/enriched data
          capway_active_status: boolean(),
          last_invoice_status: String.t() | nil,
          paid_invoices: integer() | nil,
          unpaid_invoices: integer() | nil,
          collection: integer() | nil
        }

  @derive Jason.Encoder
  defstruct national_id: nil,
            trinity_subscriber_id: nil,
            trinity_subscription_id: nil,
            capway_contract_ref: nil,
            end_date: nil,
            origin: nil,
            payment_method: nil,
            subscription_type: nil,
            trinity_status: nil,
            capway_active_status: nil,
            last_invoice_status: nil,
            paid_invoices: nil,
            unpaid_invoices: nil,
            collection: nil

  @doc """
  Converts a Trinity subscriber to canonical format.

  ## Parameters
  - `trinity_subscriber`: Trinity subscriber struct with preloaded subscription

  ## Returns
  - `%Subscribers.Canonical{}` struct
  """
  def from_trinity(%{
        personal_number: personal_number,
        subscription: subscription,
        id: trinity_subscriber_id
      }) do
    %__MODULE__{
      national_id: personal_number,
      trinity_subscriber_id: trinity_subscriber_id |> format_string_to_integer(),
      trinity_subscription_id: subscription.id,
      capway_contract_ref: nil,
      payment_method: subscription.payment_method,
      end_date: format_datetime(subscription.end_date),
      origin: :trinity,
      trinity_status: subscription.status,
      subscription_type: Map.get(subscription, :subscription_type),
      capway_active_status: nil,
      last_invoice_status: nil,
      paid_invoices: nil,
      unpaid_invoices: nil,
      collection: nil
    }
  end

  @doc """
  Converts a Capway subscriber to canonical format.

  ## Parameters
  - `capway_subscriber`: CapwaySubscriber struct from SOAP response

  ## Returns
  - `%Subscribers.Canonical{}` struct
  """
  def from_capway(%CapwaySync.Models.CapwaySubscriber{} = capway_subscriber) do
    %__MODULE__{
      national_id: capway_subscriber.id_number,
      trinity_subscriber_id: capway_subscriber.customer_ref |> format_string_to_integer(),
      trinity_subscription_id: nil,
      capway_contract_ref: capway_subscriber.contract_ref_no,
      end_date: format_datetime(capway_subscriber.end_date),
      capway_active_status: capway_subscriber.active == "true",
      last_invoice_status: capway_subscriber.last_invoice_status,
      paid_invoices: capway_subscriber.paid_invoices |> format_string_to_integer(),
      unpaid_invoices: capway_subscriber.unpaid_invoices |> format_string_to_integer(),
      collection: capway_subscriber.collection |> format_string_to_integer(),
      origin: :capway,
      payment_method: nil,
      trinity_status: nil,
      subscription_type: nil
    }
  end

  @doc """
  Converts a list of Trinity subscribers to canonical format.
  """
  def from_trinity_list(trinity_subscribers) when is_list(trinity_subscribers) do
    Enum.map(trinity_subscribers, &from_trinity/1)
  end

  @doc """
  Converts a list of Capway subscribers to canonical format.
  """
  def from_capway_list(capway_subscribers) when is_list(capway_subscribers) do
    Enum.map(capway_subscribers, &from_capway/1)
  end

  # Helper function to format DateTime/NaiveDateTime to ISO8601 string
  defp format_datetime(nil), do: nil

  defp format_datetime(%NaiveDateTime{} = datetime) do
    datetime
    |> NaiveDateTime.to_iso8601()
  end

  defp format_datetime(%DateTime{} = datetime) do
    datetime
    |> DateTime.to_iso8601()
  end

  defp format_datetime(datetime) when is_binary(datetime), do: datetime

  defp format_string_to_integer(nil), do: nil

  defp format_string_to_integer(str) when is_binary(str) do
    case Integer.parse(str) do
      {int, _} -> int
      :error -> nil
    end
  end

  defp format_string_to_integer(val), do: val
end
