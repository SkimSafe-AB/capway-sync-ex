defmodule CapwaySync.Rest.CustomerCount do
  @moduledoc """
  Module to interact with Capway's REST API to fetch customer count.
  """
  alias CapwaySync.Rest.Client
  require Logger

  def run(access_token) do
    api_url = "#{Client.get_env(:base_url)}/v1/Customers?$top=1"

    req =
      Req.get(api_url,
        headers: Client.set_std_headers(),
        auth: {:bearer, access_token}
      )
      |> Client.return_result()

    case req do
      {:ok, %{"total" => count}} -> {:ok, count}
      {:error, reason} -> {:error, reason}
    end
  end
end
