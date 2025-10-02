defmodule CapwaySync.Reactor.V1.Steps.CancelCapwayContracts do
  @moduledoc """
  Identifies subscribers that need Capway contract cancellation.

  This step analyzes subscribers that exist in both Trinity and Capway systems
  but have had their payment method changed from "capway" to something else in Trinity.
  These contracts need to be cancelled in Capway since the payment method has changed.

  ## Input
  - `comparison_result`: Results from CompareData step containing cancel_capway_contracts list

  ## Output
  Returns a map containing:
  - `cancel_capway_contracts`: List of subscriber objects that need contract cancellation
  - `cancel_capway_count`: Count of contracts to cancel
  - `total_analyzed`: Total number of potential cancellation candidates analyzed

  ## Logic
  Processes subscribers identified in comparison_result.cancel_capway_contracts:
  - These are Trinity subscribers with payment_method != "capway"
  - Who still have active contracts in Capway
  - Requiring manual intervention or automated cancellation
  """

  use Reactor.Step
  require Logger

  @impl Reactor.Step
  def run(arguments, _context, _options \\ []) do
    Logger.info("Starting Capway contract cancellation analysis")

    with {:ok, comparison_result} <- validate_argument(arguments, :comparison_result) do
      cancel_contracts = Map.get(comparison_result, :cancel_capway_contracts, [])
      total_analyzed = length(cancel_contracts)

      Logger.info("Analyzed #{total_analyzed} subscribers for contract cancellation")

      result = %{
        cancel_capway_contracts: cancel_contracts,
        cancel_capway_count: total_analyzed,
        total_analyzed: total_analyzed
      }

      if total_analyzed > 0 do
        Logger.info("🚫 Found #{total_analyzed} Capway contracts that need cancellation due to payment method changes")

        # Log sample of contracts for visibility
        sample_size = min(5, total_analyzed)
        sample_contracts = Enum.take(cancel_contracts, sample_size)

        Enum.each(sample_contracts, fn subscriber ->
          id_number = Map.get(subscriber, :id_number, "unknown")
          payment_method = Map.get(subscriber, :payment_method, "unknown")
          Logger.info("   - ID: #{id_number}, New payment method: #{payment_method}")
        end)

        if total_analyzed > sample_size do
          Logger.info("   ... and #{total_analyzed - sample_size} more")
        end
      else
        Logger.info("✅ No Capway contracts need cancellation")
      end

      {:ok, result}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @impl Reactor.Step
  def compensate(_error, _arguments, _context, _options) do
    :retry
  end

  @impl Reactor.Step
  def undo(_result, _arguments, _context, _options) do
    :ok
  end

  # Private helper functions

  defp validate_argument(arguments, key) do
    case Map.get(arguments, key) do
      nil -> {:error, "Missing required argument: #{key}"}
      value when is_map(value) -> {:ok, value}
      _ -> {:error, "Argument #{key} must be a map"}
    end
  end
end