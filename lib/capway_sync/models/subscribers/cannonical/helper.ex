defmodule CapwaySync.Models.Subscribers.Cannonical.Helper do
  @moduledoc """
  This module provides helper functions to categorize and process
  Trinity subscribers into different groups based on:
  - Active subscribers
  - Inactive subscribers
  - Subscribers with specific subscription types (e.g., "locked")
  """

  alias CapwaySync.Models.Subscribers.Cannonical

  @doc """
  Groups subscribers into categories based on the source system.

  For Trinity (:trinity):
  - active_subscribers: subscribers not cancelled or expired (keyed by trinity_subscriber_id)
  - cancelled_subscribers: subscribers that are cancelled or expired
  - locked_subscribers: active subscribers with subscription_type "locked"

  For Capway (:capway):
  - active_subscribers: active contracts (keyed by capway_contract_ref)
  - cancelled_subscribers: inactive contracts (keyed by capway_contract_ref)
  - above_collector_threshold: active contracts with collection >= 2
  """
  @spec group([Cannonical.t()], atom()) :: %{atom() => %{String.t() => Cannonical.t()}}
  def group(subscribers, source)

  def group(subscribers, :trinity) do
    active_subscribers =
      subscribers
      |> Enum.reduce(%{}, fn sub, acc ->
        if sub.trinity_status not in [:cancelled, :expired, :pending, :pending_cancel] and
             capway_metadata_older_than_yesterday?(sub) do
          Map.put(acc, sub.trinity_subscriber_id, sub)
        else
          acc
        end
      end)

    cancelled_subscribers =
      subscribers
      |> Enum.reduce(%{}, fn sub, acc ->
        if sub.trinity_status in [:cancelled, :expired] do
          Map.put(acc, sub.trinity_subscriber_id, sub)
        else
          acc
        end
      end)

    locked_subscribers =
      active_subscribers
      |> Enum.reduce(%{}, fn {_id, sub}, acc ->
        if sub.subscription_type == :locked and sub.payment_method == "capway" do
          Map.put(acc, sub.trinity_subscriber_id, sub)
        else
          acc
        end
      end)

    %{
      active_subscribers: active_subscribers,
      cancelled_subscribers: cancelled_subscribers,
      locked_subscribers: locked_subscribers,
      map_sets: %{
        active_national_ids:
          Enum.filter(active_subscribers, fn {_id, sub} ->
            presence?(sub.national_id)
          end)
          |> Enum.map(fn {_id, sub} -> sub.national_id end)
          |> MapSet.new(),
        all_national_ids:
          subscribers
          |> Enum.filter(fn sub ->
            sub.trinity_status not in [:cancelled, :expired] and presence?(sub.national_id)
          end)
          |> Enum.map(fn sub -> sub.national_id end)
          |> MapSet.new(),
        all_subscriber_ids:
          subscribers
          |> Enum.filter(fn sub ->
            sub.trinity_status not in [:cancelled, :expired] and
              presence?(sub.trinity_subscriber_id)
          end)
          |> Enum.map(fn sub -> sub.trinity_subscriber_id end)
          |> MapSet.new(),
        subscriber_to_subscription_ids:
          active_subscribers
          |> Enum.reduce(%{}, fn {_id, sub}, acc ->
            Map.put(acc, sub.trinity_subscriber_id, sub.trinity_subscription_id)
          end),
        recently_cancelled_subscriber_ids:
          subscribers
          |> Enum.filter(fn sub ->
            recently_cancelled_in_capway?(sub) and presence?(sub.trinity_subscriber_id)
          end)
          |> Enum.map(fn sub -> sub.trinity_subscriber_id end)
          |> MapSet.new(),
        recently_cancelled_national_ids:
          subscribers
          |> Enum.filter(fn sub ->
            recently_cancelled_in_capway?(sub) and presence?(sub.national_id)
          end)
          |> Enum.map(fn sub -> sub.national_id end)
          |> MapSet.new()
      }
    }
  end

  def group(subscribers, :capway) do
    {orphaned_subscribers, associated_subscribers} =
      subscribers
      |> Enum.reduce({%{}, %{}}, fn sub, {orphaned_acc, associated_acc} ->
        if presence?(sub.capway_contract_ref) do
          {orphaned_acc, Map.put(associated_acc, sub.capway_contract_ref, sub)}
        else
          {Map.put(orphaned_acc, UUID.uuid4(), sub), associated_acc}
        end
      end)

    active_subscribers =
      associated_subscribers
      |> Enum.reduce(%{}, fn {contract_ref, sub}, acc ->
        if sub.capway_active_status == true do
          Map.put(acc, contract_ref, sub)
        else
          acc
        end
      end)

    cancelled_subscribers =
      associated_subscribers
      |> Enum.reduce(%{}, fn {contract_ref, sub}, acc ->
        if sub.capway_active_status == false do
          Map.put(acc, contract_ref, sub)
        else
          acc
        end
      end)

    above_collector_threshold =
      active_subscribers
      |> Enum.reduce(%{}, fn {contract_ref, sub}, acc ->
        if sub.collection != nil and sub.collection >= 2 do
          Map.put(acc, contract_ref, sub)
        else
          acc
        end
      end)

    %{
      orphaned_subscribers: orphaned_subscribers,
      associated_subscribers: associated_subscribers,
      active_subscribers: active_subscribers,
      cancelled_subscribers: cancelled_subscribers,
      above_collector_threshold: above_collector_threshold,
      map_sets: %{
        active_national_ids:
          subscribers
          |> Enum.filter(fn sub ->
            sub.capway_active_status == true and presence?(sub.national_id)
          end)
          |> Enum.map(fn sub -> sub.national_id end)
          |> MapSet.new(),
        active_trinity_ids:
          subscribers
          |> Enum.filter(fn sub ->
            sub.capway_active_status == true and presence?(sub.trinity_subscriber_id)
          end)
          |> Enum.map(fn sub -> sub.trinity_subscriber_id end)
          |> MapSet.new()
      }
    }
  end

  @doc """
  Returns true if both `trinity_capway_last_updated` and `trinity_capway_created_at`
  are either nil or older than 1 day. If either date is younger than 1 day,
  the subscriber is considered too recent for comparison and returns false.
  """
  def capway_metadata_older_than_yesterday?(sub) do
    older_than_yesterday?(sub.trinity_capway_last_updated) and
      older_than_yesterday?(sub.trinity_capway_created_at)
  end

  defp older_than_yesterday?(nil), do: true

  defp older_than_yesterday?(date_string) when is_binary(date_string) do
    yesterday = Timex.shift(Timex.now("Etc/UTC"), days: -1)

    case Timex.parse(date_string, "{ISO:Extended}") do
      {:ok, dt} ->
        Timex.before?(dt, yesterday)

      _ ->
        case Timex.parse(date_string, "{YYYY}-{0M}-{0D}") do
          {:ok, dt} ->
            dt
            |> Timex.to_datetime("Etc/UTC")
            |> Timex.before?(yesterday)

          _ ->
            true
        end
    end
  end

  defp older_than_yesterday?(_), do: true

  @doc """
  Returns true if the subscriber has `trinity_capway_cancelled_at` set
  and it is within the last 2 days.
  """
  def recently_cancelled_in_capway?(%{trinity_capway_cancelled_at: nil}), do: false

  def recently_cancelled_in_capway?(%{trinity_capway_cancelled_at: cancelled_at})
      when is_binary(cancelled_at) do
    two_days_ago = Timex.shift(Timex.now("Etc/UTC"), days: -2)

    case Timex.parse(cancelled_at, "{ISO:Extended}") do
      {:ok, dt} ->
        Timex.after?(dt, two_days_ago)

      _ ->
        case Timex.parse(cancelled_at, "{YYYY}-{0M}-{0D}") do
          {:ok, dt} ->
            dt
            |> Timex.to_datetime("Etc/UTC")
            |> Timex.after?(two_days_ago)

          _ ->
            false
        end
    end
  end

  def recently_cancelled_in_capway?(_), do: false

  defp presence?(nil), do: false
  defp presence?(val) when is_binary(val), do: String.trim(val) != ""
  defp presence?(_), do: true
end
