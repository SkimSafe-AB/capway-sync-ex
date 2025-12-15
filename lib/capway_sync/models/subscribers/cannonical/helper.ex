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
  - active_subscribers: subscribers not cancelled or expired
  - cancelled_subscribers: subscribers that are cancelled or expired
  - locked_subscribers: active subscribers with subscription_type "locked"

  For Capway (:capway):
  - active_subscribers: subscribers with capway_active_status = true
  - cancelled_subscribers: subscribers with capway_active_status = false
  - above_collector_threshold: subscribers with collection >= 2
  """
  @spec group([Cannonical.t()], atom()) :: %{atom() => %{String.t() => Cannonical.t()}}
  def group(subscribers, :trinity) do
    active_subscribers =
      subscribers
      |> Enum.reduce(%{}, fn sub, acc ->
        if sub.trinity_status not in [:cancelled, :expired] do
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
          |> MapSet.new()
      }
    }
  end

  def group(subscribers, :capway) do
    {orphaned_subscribers, associated_subscribers} =
      subscribers
      |> Enum.reduce({%{}, %{}}, fn sub, {orphaned_acc, associated_acc} ->
        if presence?(sub.trinity_subscriber_id) do
          {orphaned_acc, Map.put(associated_acc, sub.trinity_subscriber_id, sub)}
        else
          {Map.put(orphaned_acc, sub.capway_contract_ref, sub), associated_acc}
        end
      end)

    active_subscribers =
      associated_subscribers
      |> Enum.reduce(%{}, fn {_id, sub}, acc ->
        if sub.capway_active_status == true do
          Map.put(acc, sub.trinity_subscriber_id, sub)
        else
          acc
        end
      end)

    cancelled_subscribers =
      associated_subscribers
      |> Enum.reduce(%{}, fn {_id, sub}, acc ->
        if sub.capway_active_status == false do
          Map.put(acc, sub.trinity_subscriber_id, sub)
        else
          acc
        end
      end)

    above_collector_threshold =
      associated_subscribers
      |> Enum.reduce(%{}, fn {_id, sub}, acc ->
        if sub.collection != nil and sub.collection >= 2 do
          Map.put(acc, sub.trinity_subscriber_id, sub)
        else
          acc
        end
      end)

    %{
      orphaned_subscribers: orphaned_subscribers,
      active_subscribers: active_subscribers,
      cancelled_subscribers: cancelled_subscribers,
      above_collector_threshold: above_collector_threshold,
      map_sets: %{
        active_national_ids:
          Enum.filter(active_subscribers, fn {_id, sub} ->
            presence?(sub.national_id)
          end)
          |> Enum.map(fn {_id, sub} -> sub.national_id end)
          |> MapSet.new(),
        active_trinity_ids:
          Enum.filter(active_subscribers, fn {_id, sub} ->
            presence?(sub.trinity_subscriber_id)
          end)
          |> Enum.map(fn {_id, sub} -> sub.trinity_subscriber_id end)
          |> MapSet.new()
      }
    }
  end

  defp presence?(nil), do: false
  defp presence?(val) when is_binary(val), do: String.trim(val) != ""
  defp presence?(_), do: true
end
