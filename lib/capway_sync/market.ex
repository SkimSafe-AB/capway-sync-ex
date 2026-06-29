defmodule CapwaySync.Market do
  @moduledoc """
  Central registry of per-market settings.

  The *active* market is selected at runtime by the `MARKET` env var (surfaced
  as `:capway_sync, :market`, see `config/runtime.exs`). Everything that varies
  by market as a matter of business logic — e.g. the expected customer
  `languageCode` — is defined here as a predefined value rather than as its own
  environment variable. Adding a market, or a new per-market setting, means
  editing the `@settings` map below, not wiring up new configuration.

  This intentionally does **not** cover deployment-level configuration such as
  credentials, hosts, or DynamoDB table names — those are per-environment
  secrets/infra and stay in env vars.

  ## Examples

      iex> CapwaySync.Market.language_code(:se)
      "sv"

      iex> CapwaySync.Market.language_code(:no)
      "nb"

      iex> CapwaySync.Market.currency_code(:se)
      "SEK"

      # Unknown market → nil; callers treat this as "cannot determine".
      iex> CapwaySync.Market.language_code(:dk)
      nil
  """

  @type t :: atom()

  # Per-market settings. Language codes are lowercase and currency codes are
  # uppercase ISO 4217 — comparisons normalise the incoming value to the same
  # case before matching.
  @settings %{
    se: %{language_code: "sv", currency_code: "SEK"},
    no: %{language_code: "nb", currency_code: "NOK"}
  }

  @default_market :se

  @doc """
  The active market atom, read from `:capway_sync, :market`.

  Defaults to `#{inspect(@default_market)}` when unset.
  """
  @spec current() :: t()
  def current, do: Application.get_env(:capway_sync, :market, @default_market)

  @doc "All settings for the active market (empty map if the market is unknown)."
  @spec settings() :: map()
  def settings, do: settings(current())

  @doc "All settings for a given market (empty map if the market is unknown)."
  @spec settings(t()) :: map()
  def settings(market), do: Map.get(@settings, market, %{})

  @doc """
  Expected Capway `languageCode` for the active market.

  Returns `nil` when the market has no defined language — callers should treat
  `nil` as "cannot determine" and skip language-based actions.
  """
  @spec language_code() :: String.t() | nil
  def language_code, do: language_code(current())

  @doc "Expected Capway `languageCode` for the given market (`nil` if undefined)."
  @spec language_code(t()) :: String.t() | nil
  def language_code(market), do: settings(market)[:language_code]

  @doc """
  Expected Capway `currencyCode` (ISO 4217) for the active market.

  Returns `nil` when the market has no defined currency — callers should treat
  `nil` as "cannot determine" and skip currency-based actions.
  """
  @spec currency_code() :: String.t() | nil
  def currency_code, do: currency_code(current())

  @doc "Expected Capway `currencyCode` for the given market (`nil` if undefined)."
  @spec currency_code(t()) :: String.t() | nil
  def currency_code(market), do: settings(market)[:currency_code]
end
