defmodule CapwaySync.Models.Subscribers.Cannonical.Helper do
  @moduledoc """
  This module provides helper functions to categorize and process
  Trinity subscribers into different groups based on:
  - Active subscribers
  - Inactive subscribers
  - Subscribers with specific subscription types (e.g., "locked")
  """

  alias CapwaySync.Models.Subscribers.Cannonical

  @spec group([Cannonical.t()], atom()) :: [[Cannonical.t()]]
  def group(subscribers, :trinity) do
    active_subscribers =
      Enum.filter(subscribers, fn sub -> sub.trinity_status not in [:cancelled, :expired] end)

    inactive_subscribers =
      Enum.filter(subscribers, fn sub -> sub.trinity_status in [:cancelled, :expired] end)

    locked_subscribers =
      Enum.filter(active_subscribers, fn sub -> sub.subscription_type == "locked" end)

    %{
      active_subscribers: %{
        data: active_subscribers,
        map_set: MapSet.new(Enum.map(active_subscribers, & &1.trinity_subscriber_id))
      },
      inactive_subscribers: %{
        data: inactive_subscribers,
        map_set: MapSet.new(Enum.map(inactive_subscribers, & &1.trinity_subscriber_id))
      },
      locked_subscribers: %{
        data: locked_subscribers,
        map_set: MapSet.new(Enum.map(locked_subscribers, & &1.trinity_subscriber_id))
      }
    }
  end

  def group(subscribers, :capway) do
    active_subscribers =
      Enum.filter(subscribers, fn sub -> sub.capway_active_status == true end)

    inactive_subscribers =
      Enum.filter(subscribers, fn sub -> sub.capway_active_status == false end)

    above_collector_threshold =
      Enum.filter(subscribers, fn sub -> sub.collection != nil and sub.collection >= 2 end)

    %{
      active_subscribers: %{
        data: active_subscribers,
        map_set: MapSet.new(Enum.map(active_subscribers, & &1.trinity_subscriber_id))
      },
      inactive_subscribers: %{
        data: inactive_subscribers,
        map_set: MapSet.new(Enum.map(inactive_subscribers, & &1.trinity_subscriber_id))
      },
      above_collector_threshold: %{
        data: above_collector_threshold,
        map_set: MapSet.new(Enum.map(above_collector_threshold, & &1.trinity_subscriber_id))
      }
    }
  end
end
