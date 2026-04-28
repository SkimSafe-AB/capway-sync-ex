defmodule CapwaySync.Clients.PaymentProcessor.Client do
  @moduledoc """
  Read-only client for the Payment Processor REST API.

  This sync app only needs to *read* customer data from the payment processor —
  the actual write/PATCH operations are owned by the Trinity-side client.

  Mirrors the per-customer fetch pattern in
  `Trinity.Clients.PaymentProcessor.Client.get_capway_customer_by_id/1`.
  """

  require Logger

  @doc """
  Fetches a Capway customer from the payment processor by their Capway customer ID.

  Calls `GET <host>v3/capway/customers/by_customer_id/:customer_id`.

  ## Returns
    - `{:ok, map()}` — decoded JSON body on 200
    - `{:error, :not_found}` — 404
    - `{:error, term()}` — non-2xx body or transport error
  """
  @spec get_capway_customer_by_id(String.t()) ::
          {:ok, map()} | {:error, :not_found} | {:error, term()}
  def get_capway_customer_by_id(customer_id) when is_binary(customer_id) do
    url = host() <> "v3/capway/customers/by_customer_id/#{customer_id}"

    case request(:get, url) do
      {:ok, %Req.Response{status: 200, body: body}} when is_map(body) ->
        {:ok, body}

      {:ok, %Req.Response{status: 200, body: body}} when is_binary(body) ->
        decode_body(body)

      {:ok, %Req.Response{status: 404}} ->
        {:error, :not_found}

      {:ok, %Req.Response{status: status, body: body}} ->
        Logger.error(
          "Error fetching capway customer by ID #{customer_id}: status #{status}, #{inspect(body)}"
        )

        {:error, body}

      {:error, reason} ->
        Logger.error(
          "Error fetching capway customer by ID #{customer_id}: #{inspect(reason)}"
        )

        {:error, reason}
    end
  end

  defp request(method, url) do
    options =
      [
        method: method,
        url: url,
        headers: [{"content-type", "application/json"}, {"accept", "application/json"}],
        receive_timeout: 180_000,
        connect_options: [transport_opts: [verify: :verify_none]]
      ]
      |> Keyword.merge(req_options())

    Req.request(options)
  end

  defp decode_body(""), do: {:ok, %{}}

  defp decode_body(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} -> {:ok, decoded}
      {:error, reason} -> {:error, reason}
    end
  end

  defp host do
    Application.get_env(:capway_sync, :payment_processor)[:host] ||
      raise "host is not set in :capway_sync, :payment_processor"
  end

  # Allow tests to inject a Req plug via Application config without coupling
  # the production code path to test-only knobs.
  defp req_options do
    Application.get_env(:capway_sync, :payment_processor, [])
    |> Keyword.take([:plug, :adapter])
  end
end
