defmodule CapwaySync.Models.Subscribers.Cannonical.Helper do
  @moduledoc """
  This module provides helper functions to categorize and process
  Trinity subscribers into different groups based on:
  - Active subscribers
  - Inactive subscribers
  - Subscribers with specific subscription types (e.g., "locked")
  """

  alias CapwaySync.Models.Subscribers.Cannonical

  @spec group([Cannonical.t()], atom()) :: %{atom() => %{String.t() => Cannonical.t()}}
  @doc """
  Groups Trinity subscribers into categories:
  - active_subscribers: subscribers not cancelled or expired
  - inactive_subscribers: subscribers that are cancelled or expired
  - locked_subscribers: active subscribers with subscription_type "locked"
  """
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

    inactive_subscribers =
      subscribers
      |> Enum.reduce(%{}, fn sub, acc ->
        if sub.trinity_status in [:cancelled, :expired] do
          Map.put(acc, sub.trinity_subscriber_id, sub)
        else
          acc
        end
      end)

    locked_subscribers =
      subscribers
      |> Enum.reduce(%{}, fn sub, acc ->
        if sub.trinity_status not in [:cancelled, :expired] and sub.subscription_type == "locked" do
          Map.put(acc, sub.trinity_subscriber_id, sub)
        else
          acc
        end
      end)

    %{
      active_subscribers: active_subscribers,
      inactive_subscribers: inactive_subscribers,
      locked_subscribers: locked_subscribers
    }
  end

  @doc """
  Groups Capway subscribers into categories:
  - active_subscribers: subscribers with capway_active_status = true
  - inactive_subscribers: subscribers with capway_active_status = false
  - above_collector_threshold: subscribers with collection >= 2
  """
  def group(subscribers, :capway) do
    active_subscribers =
      subscribers
      |> Enum.reduce(%{}, fn sub, acc ->
        if sub.capway_active_status == true do
          Map.put(acc, sub.trinity_subscriber_id, sub)
        else
          acc
        end
      end)

    inactive_subscribers =
      subscribers
      |> Enum.reduce(%{}, fn sub, acc ->
        if sub.capway_active_status == false do
          Map.put(acc, sub.trinity_subscriber_id, sub)
        else
          acc
        end
      end)

    above_collector_threshold =
      subscribers
      |> Enum.reduce(%{}, fn sub, acc ->
        if sub.collection != nil and sub.collection >= 2 do
          Map.put(acc, sub.trinity_subscriber_id, sub)
        else
          acc
        end
      end)

    %{
      active_subscribers: active_subscribers,
      inactive_subscribers: inactive_subscribers,
      above_collector_threshold: above_collector_threshold
    }
  end
end
