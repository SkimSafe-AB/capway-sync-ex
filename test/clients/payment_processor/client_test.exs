defmodule CapwaySync.Clients.PaymentProcessor.ClientTest do
  use ExUnit.Case, async: false

  alias CapwaySync.Clients.PaymentProcessor.Client

  @host "https://payment-processor.test/api/"

  setup do
    Application.put_env(:capway_sync, :payment_processor, host: @host)

    on_exit(fn ->
      Application.delete_env(:capway_sync, :payment_processor)
    end)

    :ok
  end

  defp with_adapter(fun) when is_function(fun, 1) do
    cfg = Application.get_env(:capway_sync, :payment_processor, [])
    Application.put_env(:capway_sync, :payment_processor, Keyword.put(cfg, :adapter, fun))
  end

  defp respond(status, body, request) do
    response =
      Req.Response.new(status: status)
      |> then(fn r ->
        cond do
          is_binary(body) -> %{r | body: body}
          is_map(body) -> %{r | body: body}
          true -> r
        end
      end)

    {request, response}
  end

  test "returns the decoded body on 200" do
    expected_url = "#{@host}v3/capway/customers/by_customer_id/CID-001"

    with_adapter(fn req ->
      assert URI.to_string(req.url) == expected_url
      assert req.method == :get
      respond(200, %{"email" => "alice@example.com", "id" => "CID-001"}, req)
    end)

    assert {:ok, %{"email" => "alice@example.com"}} =
             Client.get_capway_customer_by_id("CID-001")
  end

  test "decodes JSON when the body comes back as a string" do
    with_adapter(fn req ->
      respond(200, ~s({"email":"alice@example.com"}), req)
    end)

    assert {:ok, %{"email" => "alice@example.com"}} =
             Client.get_capway_customer_by_id("CID-001")
  end

  test "returns :not_found on 404" do
    with_adapter(fn req -> respond(404, "", req) end)

    assert {:error, :not_found} = Client.get_capway_customer_by_id("missing")
  end

  test "returns the error body on non-2xx" do
    with_adapter(fn req -> respond(500, %{"error" => "kaboom"}, req) end)

    assert {:error, %{"error" => "kaboom"}} =
             Client.get_capway_customer_by_id("CID-001")
  end

  test "returns the transport error on adapter failure" do
    with_adapter(fn req -> {req, %RuntimeError{message: "connection refused"}} end)

    assert {:error, %RuntimeError{message: "connection refused"}} =
             Client.get_capway_customer_by_id("CID-001")
  end

  test "raises a clear error if host is not configured" do
    Application.delete_env(:capway_sync, :payment_processor)

    assert_raise RuntimeError, ~r/host is not set/, fn ->
      Client.get_capway_customer_by_id("CID-001")
    end
  end
end
