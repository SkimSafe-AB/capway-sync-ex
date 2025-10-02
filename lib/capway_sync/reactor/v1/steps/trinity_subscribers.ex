defmodule CapwaySync.Reactor.V1.Steps.TrinitySubscribers do
  use Reactor.Step
  alias CapwaySync.Ecto.TrinitySubscribers

  @impl true
  def run(_map, _context, _options) do
    require Logger

    case System.get_env("USE_MOCK_TRINITY") do
      "true" ->
        subscribers = generate_mock_trinity_data()
        Logger.info("🎭 Using mock Trinity data: #{length(subscribers)} subscribers")
        {:ok, subscribers}

      _ ->
        try do
          subscribers = TrinitySubscribers.list_subscribers(true)
          Logger.info("Successfully fetched #{length(subscribers)} Trinity subscribers")
          {:ok, subscribers}
        rescue
          error ->
            Logger.error("Failed to fetch Trinity subscribers: #{inspect(error)}")
            {:error, {:trinity_fetch_error, error}}
        end
    end
  end

  @impl true
  def compensate(_error, _arguments, _context, _options) do
    :retry
  end

  @impl true
  def undo(_map, _context, _options, _step_options) do
    :ok
  end

  # Generates mock Trinity data in the raw format that the conversion step expects
  # This creates realistic test scenarios when used with mock Capway data
  defp generate_mock_trinity_data do
    [
      # Subscribers that exist in both systems (will be in existing_in_both)
      %{
        personal_number: "195712260115",
        id: 1001,
        subscription: %{
          id: 2001,
          payment_method: "capway",
          status: :active,
          end_date: nil
        }
      },
      %{
        personal_number: "198311074051",
        id: 1002,
        subscription: %{
          id: 2002,
          payment_method: "capway",
          status: :active,
          end_date: nil
        }
      },

      # Subscriber who changed payment method (will trigger cancel_capway_contracts)
      %{
        personal_number: "196304014878",
        id: 1003,
        subscription: %{
          id: 2003,
          payment_method: "bank",  # Changed from capway to bank
          status: :active,
          end_date: nil
        }
      },

      # New Trinity subscribers with capway payment method (will be missing_in_capway)
      %{
        personal_number: "999888777666",
        id: 1004,
        subscription: %{
          id: 2004,
          payment_method: "capway",
          status: :active,
          end_date: nil
        }
      },
      %{
        personal_number: "999888777777",
        id: 1005,
        subscription: %{
          id: 2005,
          payment_method: "capway",
          status: :active,
          end_date: nil
        }
      },

      # New Trinity subscribers with other payment methods (will be missing_in_capway)
      %{
        personal_number: "888777666555",
        id: 1006,
        subscription: %{
          id: 2006,
          payment_method: "bank",
          status: :active,
          end_date: nil
        }
      },
      %{
        personal_number: "777666555444",
        id: 1007,
        subscription: %{
          id: 2007,
          payment_method: "card",
          status: :active,
          end_date: nil
        }
      }

      # Note: Legacy contracts 199001011234 and 199002022345 exist in Capway
      # but are NOT in this Trinity list, so they will be missing_in_trinity
    ]
  end
end
