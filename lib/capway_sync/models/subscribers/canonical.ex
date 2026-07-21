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
  - `subscription_type`: Subscription type from Trinity (e.g., "locked", nil for Capway data).
    A `:sinfrid` type causes `capway_sync_excluded` to be set to `true`.
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
          trinity_subscription_updated_at: DateTime.t() | nil,
          capway_contract_ref: String.t(),
          capway_contract_guid: String.t() | nil,
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
          collection: integer() | nil,
          capway_customer_id: String.t() | nil,
          capway_contract_price: String.t() | nil,
          capway_next_invoice_date: String.t() | nil,
          # Capway metadata stored in Trinity
          trinity_capway_last_updated: String.t() | nil,
          trinity_capway_created_at: String.t() | nil,
          trinity_capway_cancelled_at: String.t() | nil,
          # Capway direct debit mandate GUID stored in Trinity subscriber
          # metadata (`capway_mandate_guid`, written by Trinity when the
          # autogiro mandate is created). `nil`/blank means no mandate exists.
          trinity_capway_mandate_guid: String.t() | nil,
          # Last mandate-creation failure recorded by Trinity's PaymentService
          # (`capway_mandate_error` / `capway_mandate_error_at` metadata).
          # Used to enrich the `capway_create_mandate` action-item comment.
          trinity_capway_mandate_error: String.t() | nil,
          trinity_capway_mandate_error_at: String.t() | nil,
          # Sync exclusion flag
          capway_sync_excluded: boolean(),
          # Email address — populated from Trinity in `from_trinity/1` and from
          # the payment processor REST API (via the FetchCapwayEmails step) for
          # Capway-originated entries. `nil` means "not yet known", which the
          # comparison treats as a no-op.
          email: String.t() | nil,
          # Capway customer `languageCode`, backfilled by the FetchCapwayEmails
          # step from the payment processor REST API (Capway-originated entries
          # only — there is no Trinity equivalent). Tri-state:
          #   * `nil`  — never fetched ("unknown"); the comparison ignores it,
          #              so a failed/absent REST fetch can't trigger a false update.
          #   * `""`   — fetched but the record had no/blank language; counts as
          #              wrong and triggers an update to the market default.
          #   * value  — the fetched code, compared against the market default.
          language_code: String.t() | nil,
          # Capway customer `currencyCode` (ISO 4217), backfilled by the
          # FetchCapwayEmails step. Same tri-state semantics as `language_code`
          # (`nil` = not fetched/unknown, `""` = fetched-but-blank/wrong, value
          # = the fetched code), compared against the market default currency.
          currency_code: String.t() | nil
        }

  @derive Jason.Encoder
  defstruct national_id: nil,
            trinity_subscriber_id: nil,
            trinity_subscription_id: nil,
            trinity_subscription_updated_at: nil,
            capway_contract_ref: nil,
            capway_contract_guid: nil,
            end_date: nil,
            origin: nil,
            payment_method: nil,
            subscription_type: nil,
            trinity_status: nil,
            capway_active_status: nil,
            last_invoice_status: nil,
            paid_invoices: nil,
            unpaid_invoices: nil,
            collection: nil,
            capway_customer_id: nil,
            capway_contract_price: nil,
            capway_next_invoice_date: nil,
            trinity_capway_last_updated: nil,
            trinity_capway_created_at: nil,
            trinity_capway_cancelled_at: nil,
            trinity_capway_mandate_guid: nil,
            trinity_capway_mandate_error: nil,
            trinity_capway_mandate_error_at: nil,
            capway_sync_excluded: false,
            email: nil,
            language_code: nil,
            currency_code: nil

  @doc """
  Converts a Trinity subscriber to canonical format.

  ## Parameters
  - `trinity_subscriber`: Trinity subscriber struct with preloaded subscription

  ## Returns
  - `%Subscribers.Canonical{}` struct
  """
  def from_trinity(
        %{
          personal_number: personal_number,
          subscription: subscription,
          id: trinity_subscriber_id
        } = subscriber
      ) do
    metadata = Map.get(subscriber, :metadata, [])
    subscription_type = Map.get(subscription, :subscription_type)

    %__MODULE__{
      national_id: personal_number,
      trinity_subscriber_id: trinity_subscriber_id |> format_string_to_integer(),
      trinity_subscription_id: subscription.id,
      trinity_subscription_updated_at: subscription.updated_at,
      capway_contract_ref: nil,
      capway_contract_guid: nil,
      payment_method: subscription.payment_method,
      end_date: format_datetime(subscription.end_date),
      origin: :trinity,
      trinity_status: subscription.status,
      subscription_type: subscription_type,
      capway_active_status: nil,
      last_invoice_status: nil,
      paid_invoices: nil,
      unpaid_invoices: nil,
      collection: nil,
      trinity_capway_last_updated: find_metadata_value(metadata, "capway_last_updated"),
      trinity_capway_created_at: find_metadata_value(metadata, "capway_created_at"),
      trinity_capway_cancelled_at: find_metadata_value(metadata, "capway_cancelled_at"),
      trinity_capway_mandate_guid: find_metadata_value(metadata, "capway_mandate_guid"),
      trinity_capway_mandate_error: find_metadata_value(metadata, "capway_mandate_error"),
      trinity_capway_mandate_error_at: find_metadata_value(metadata, "capway_mandate_error_at"),
      # Sinfrid subscriptions are excluded from the Capway sync entirely. We map
      # them onto the existing `capway_sync_excluded` flag (rather than dropping
      # them from the Trinity list) so they remain present in the national_id /
      # subscriber_id map sets — that keeps `get_contracts_to_cancel/7` from
      # wrongly treating an existing sinfrid Capway contract as orphaned and
      # cancelling it, while still suppressing all create/update/suspend actions.
      capway_sync_excluded:
        find_metadata_value(metadata, "capway_sync_excluded") == "true" or
          sinfrid?(subscription_type),
      email: Map.get(subscriber, :email)
    }
  end

  # Treat sinfrid subscriptions as excluded from the Capway sync. Accepts both
  # the Ecto.Enum atom (`:sinfrid`) and its string form for robustness against
  # raw/mock data sources.
  defp sinfrid?(:sinfrid), do: true
  defp sinfrid?("sinfrid"), do: true
  defp sinfrid?(_), do: false

  @doc """
  Converts a Capway subscriber to canonical format.

  ## Parameters
  - `capway_subscriber`: CapwaySubscriber struct from SOAP response

  ## Returns
  - `%Subscribers.Canonical{}` struct
  """
  def from_capway(%CapwaySync.Models.CapwaySubscriber{} = capway_subscriber) do
    {wps_id, subscriber_id} = parse_customer_ref(capway_subscriber.customer_ref)

    %__MODULE__{
      national_id: capway_subscriber.id_number,
      trinity_subscriber_id: subscriber_id,
      trinity_subscription_id: wps_id,
      trinity_subscription_updated_at: nil,
      capway_contract_ref: capway_subscriber.contract_ref_no,
      capway_contract_guid: capway_subscriber.customer_guid,
      end_date: format_datetime(capway_subscriber.end_date),
      capway_active_status: capway_subscriber.active == "true",
      last_invoice_status: capway_subscriber.last_invoice_status,
      paid_invoices: capway_subscriber.paid_invoices |> format_string_to_integer(),
      unpaid_invoices: capway_subscriber.unpaid_invoices |> format_string_to_integer(),
      collection: capway_subscriber.collection |> format_string_to_integer(),
      capway_customer_id: capway_subscriber.customer_id,
      capway_contract_price: capway_subscriber.contract_price,
      capway_next_invoice_date: capway_subscriber.next_invoice_date,
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

  @doc """
  Parses a Capway `customer_ref` into `{wps_id, trinity_subscriber_id}`.

  Recognised shapes (see `TrinityWeb.Admin.CapwayController.build_customer_reference/1`):

    * `"v{N}-<wps>-<sub>-<nanoid>"`            → `{wps_int, sub_int}`
    * `"v{N}-<wps>-NO_TRIN_SUB-<nanoid>"`      → `{wps_int, nil}`
    * `"v{N}-NO_WPS_ID-<sub>-<nanoid>"`        → `{nil, sub_int}`
    * Plain integer string (legacy)            → `{nil, sub_int}`
    * `nil` / unparseable                       → `{nil, nil}`

  Sentinel segments (`NO_WPS_ID`, `NO_TRIN_SUB`) and any segment that doesn't
  parse cleanly as an integer come back as `nil` for that slot.
  """
  @spec parse_customer_ref(String.t() | nil) :: {integer() | nil, integer() | nil}
  def parse_customer_ref(nil), do: {nil, nil}

  def parse_customer_ref(ref) when is_binary(ref) do
    with [version, wps, sub, _nanoid] <- String.split(ref, "-", parts: 4),
         true <- versioned?(version) do
      {segment_to_integer(wps), segment_to_integer(sub)}
    else
      _ -> {nil, format_string_to_integer(ref)}
    end
  end

  def parse_customer_ref(_), do: {nil, nil}

  defp versioned?(<<v, rest::binary>>) when v in [?v, ?V] and byte_size(rest) > 0,
    do: rest =~ ~r/^\d+$/

  defp versioned?(_), do: false

  defp segment_to_integer("NO_WPS_ID"), do: nil
  defp segment_to_integer("NO_TRIN_SUB"), do: nil
  defp segment_to_integer(segment), do: format_string_to_integer(segment)

  defp find_metadata_value(metadata, key) when is_list(metadata) do
    case Enum.find(metadata, fn m -> m.key == key end) do
      nil -> nil
      m -> m.value
    end
  end

  defp find_metadata_value(_, _), do: nil
end
