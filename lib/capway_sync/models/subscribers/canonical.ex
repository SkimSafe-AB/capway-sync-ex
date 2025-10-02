defmodule CapwaySync.Models.Subscribers.Canonical do
  @moduledoc """
  Canonical representation of a subscriber for cross-system comparison.

  This struct provides a unified format for comparing subscribers from different
  systems (Trinity, Capway) without coupling domain-specific data structures.
  Both Trinity and Capway data are converted to this canonical format for
  consistent comparison logic.

  ## Fields

  - `id_number`: Unique identifier (personal number) for comparison
  - `trinity_id`: Original Trinity subscriber ID (if from Trinity)
  - `capway_id`: Original Capway customer reference (if from Capway)
  - `contract_ref`: Contract reference number
  - `payment_method`: Payment method (Trinity-specific, nil for Capway data)
  - `active`: Whether the subscription/contract is active
  - `end_date`: Subscription/contract end date
  - `origin`: Source system (:trinity or :capway)

  ## Usage

      # Convert Trinity subscriber to canonical format
      canonical = Subscribers.Canonical.from_trinity(trinity_subscriber)

      # Convert Capway subscriber to canonical format
      canonical = Subscribers.Canonical.from_capway(capway_subscriber)
  """

  @type t :: %__MODULE__{
          id_number: String.t(),
          trinity_id: String.t() | nil,
          capway_id: String.t() | nil,
          contract_ref: String.t(),
          payment_method: String.t() | nil,
          active: boolean(),
          end_date: NaiveDateTime.t() | nil,
          origin: :trinity | :capway
        }

  @derive Jason.Encoder
  defstruct id_number: nil,
            trinity_id: nil,
            capway_id: nil,
            contract_ref: nil,
            payment_method: nil,
            active: false,
            end_date: nil,
            origin: nil

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
        id: trinity_id
      }) do
    %__MODULE__{
      id_number: personal_number,
      trinity_id: trinity_id,
      capway_id: nil,
      contract_ref: to_string(subscription.id),
      payment_method: subscription.payment_method,
      active: subscription.status == :active,
      end_date: subscription.end_date,
      origin: :trinity
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
      id_number: capway_subscriber.id_number,
      trinity_id: nil,
      capway_id: capway_subscriber.customer_ref,
      contract_ref: capway_subscriber.contract_ref_no,
      payment_method: nil,
      active: capway_subscriber.active,
      end_date: capway_subscriber.end_date,
      origin: :capway
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
end