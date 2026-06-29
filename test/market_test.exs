defmodule CapwaySync.MarketTest do
  # async: false — these tests flip the global :capway_sync, :market env.
  use ExUnit.Case, async: false

  alias CapwaySync.Market

  defp put_market(market) do
    previous = Application.get_env(:capway_sync, :market)
    Application.put_env(:capway_sync, :market, market)
    on_exit(fn -> Application.put_env(:capway_sync, :market, previous) end)
  end

  describe "language_code/1" do
    test "maps :se to \"sv\"" do
      assert Market.language_code(:se) == "sv"
    end

    test "maps :no to \"nb\"" do
      assert Market.language_code(:no) == "nb"
    end

    test "returns nil for an unknown market" do
      assert Market.language_code(:dk) == nil
    end
  end

  describe "currency_code/1" do
    test "maps :se to \"SEK\"" do
      assert Market.currency_code(:se) == "SEK"
    end

    test "maps :no to \"NOK\"" do
      assert Market.currency_code(:no) == "NOK"
    end

    test "returns nil for an unknown market" do
      assert Market.currency_code(:dk) == nil
    end
  end

  describe "current/0 and the active-market helpers" do
    test "current/0 reflects the configured market" do
      put_market(:no)
      assert Market.current() == :no
      assert Market.language_code() == "nb"
      assert Market.currency_code() == "NOK"
    end

    test "the active-market helpers follow the configured market" do
      put_market(:se)
      assert Market.language_code() == "sv"
      assert Market.currency_code() == "SEK"
    end
  end

  describe "settings/1" do
    test "returns the full settings map for a known market" do
      assert Market.settings(:se) == %{language_code: "sv", currency_code: "SEK"}
    end

    test "returns an empty map for an unknown market" do
      assert Market.settings(:dk) == %{}
    end
  end
end
