defmodule CapwaySync.EventDriven.Mailer do
  require Logger

  # When calling the event driven plugin we use the following struct for mailer events,
  # This includes creating and updating the contact

  # %{
  #   ref: [some unique value that related to the action, could be action+user-id],
  #   timestamp: [Some time that might be on a minute or hourly basis to avoid spam]
  #   event: :monitored_object_event, <-- The email event
  #   data: %{
  #     email: "philip+123@skimsafe.se", <-- To whom we send the email to
  #     parameters: %{event_type: "spycloud"}, <-- Params for the transactional email
  #     contact_properties: %{first_name: "Philip", last_name: "Skimsafe"}, <-- user properties
  #     template_id: "367" <-- Optional
  #   }
  # }

  @doc """
    Available events:
    field(:event, Ecto.Enum, values: [
      :create_contact,
      :update_contact,
      :delete_contact,
      :order_confirmation,
      :reset_password,
      :one_time_password,
      :verify_email,
      :monitored_object_event,
      :registration_invitation,
      :invoice,
      :custom
    ])
  """

  def trigger_email(user \\ nil, event, params \\ %{}, template_id \\ nil, email \\ nil) do
    # Check if user is available or not before setting any contact properties
    contact_properties =
      case user do
        nil ->
          %{}

        _ ->
          contact_properties(user, params)
      end

    # If email attribute has been provided, that's what we will use
    email =
      case email do
        nil -> user.email
        _ -> email
      end

    ref =
      case event do
        :verify_email ->
          case user do
            nil -> "verify_email_#{email}"
            _ -> "verify_email_#{user.id}_#{email}"
          end

        _ ->
          case user do
            nil -> "#{to_str(event)}_#{email}"
            _ -> "#{to_str(event)}_#{user.id}"
          end
      end

    event =
      create_event(
        ref,
        :seconds,
        event,
        email,
        params,
        contact_properties,
        template_id
      )

    Logger.debug("Sending email: #{event.event}")
    Logger.debug("Event: #{inspect(event)}")

    evb = EventBased.init(:email, event, [])
    Logger.debug("EventBased: #{inspect(evb)}")

    evb |> EventBased.send()
  end

  def create_event(
        ref,
        interval,
        event,
        email,
        params \\ %{},
        contact_properties \\ %{},
        template_id \\ nil
      ) do
    # Use Timex to get the different intervals
    # Lastly convert it to string
    timestamp_for_ref =
      case interval do
        :seconds -> Timex.Duration.epoch(interval)
        :minutes -> Timex.Duration.epoch(interval)
        :hours -> Timex.Duration.epoch(interval)
        :days -> Timex.Duration.epoch(interval)
        _ -> Timex.Duration.epoch(:minutes)
      end
      |> to_str()

    # get the current time
    timestamp = Timex.now() |> Timex.to_unix()

    event = %{
      ref: ref <> "_" <> timestamp_for_ref,
      timestamp: timestamp,
      event: event,
      data: %{
        email: email,
        contact_properties: contact_properties
      }
    }

    data = event.data

    data =
      if params != %{} do
        IO.puts("INSERT PARAMETERS")
        Map.put(data, :parameters, params)
      else
        data
      end

    data =
      if template_id != nil do
        Map.put(data, :template_id, template_id)
      else
        data
      end

    event = Map.put(event, :data, data)
    event
  end

  def contact_properties(user, params \\ %{}) do
    %{
      # main contact fields
      first_name: user.first_name,
      last_name: user.last_name
    }
    |> remove_when_empty([:first_name, :last_name])
  end

  defp remove_when_empty(map, []), do: map

  defp remove_when_empty(map, [field | tail]) do
    if(is_nil(map[field]) or map[field] == "") do
      remove_when_empty(Map.delete(map, field), tail)
    else
      remove_when_empty(map, tail)
    end
  end

  defp to_str(value) when is_atom(value), do: Atom.to_string(value)
  defp to_str(value) when is_integer(value), do: Integer.to_string(value)
  defp to_str(value) when is_float(value), do: Float.to_string(value)
  defp to_str(value), do: value
end
