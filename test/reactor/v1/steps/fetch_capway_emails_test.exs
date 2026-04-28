defmodule CapwaySync.Reactor.V1.Steps.FetchCapwayEmailsTest do
  use ExUnit.Case, async: false

  alias CapwaySync.Reactor.V1.Steps.FetchCapwayEmails
  alias CapwaySync.Models.Subscribers.Canonical

  defmodule MockClient do
    @moduledoc false
    # Responses are keyed in the application env. `async: false` on the test
    # case ensures we don't trample concurrent tests, and the worker tasks
    # spawned by Task.async_stream all read from the same shared env.
    def get_capway_customer_by_id(customer_id) do
      responses = Application.get_env(:capway_sync, :__test_pp_responses__, %{})
      Map.get(responses, customer_id, {:error, :not_found})
    end
  end

  setup do
    Application.put_env(:capway_sync, :payment_processor_client, MockClient)
    Application.put_env(:capway_sync, :__test_pp_responses__, %{})

    on_exit(fn ->
      Application.delete_env(:capway_sync, :payment_processor_client)
      Application.delete_env(:capway_sync, :__test_pp_responses__)
    end)

    :ok
  end

  defp set_responses(responses) do
    Application.put_env(:capway_sync, :__test_pp_responses__, responses)
  end

  defp build_capway(attrs) do
    Map.merge(
      %Canonical{
        national_id: "196403273813",
        trinity_subscriber_id: 1,
        capway_contract_ref: "C-001",
        capway_customer_id: "CID-001",
        origin: :capway,
        email: nil
      },
      attrs
    )
  end

  defp build_trinity(attrs) do
    Map.merge(
      %Canonical{
        national_id: "196403273813",
        trinity_subscriber_id: 1,
        origin: :trinity,
        capway_sync_excluded: false
      },
      attrs
    )
  end

  defp args(capway_active, trinity_active) do
    %{
      data: %{
        capway: %{active_subscribers: capway_active},
        trinity: %{active_subscribers: trinity_active}
      }
    }
  end

  test "merges fetched email into capway active_subscribers" do
    set_responses(%{"CID-001" => {:ok, %{"email" => "found@example.com"}}})

    capway_sub = build_capway(%{capway_customer_id: "CID-001"})
    trinity_sub = build_trinity(%{})

    {:ok, result} =
      FetchCapwayEmails.run(args(%{"C-001" => capway_sub}, %{1 => trinity_sub}), %{}, [])

    assert result.capway.active_subscribers["C-001"].email == "found@example.com"
    # Trinity side is left untouched.
    assert result.trinity.active_subscribers[1] == trinity_sub
  end

  test "leaves email nil when payment processor returns :not_found" do
    set_responses(%{"CID-001" => {:error, :not_found}})

    capway_sub = build_capway(%{capway_customer_id: "CID-001"})
    trinity_sub = build_trinity(%{})

    {:ok, result} =
      FetchCapwayEmails.run(args(%{"C-001" => capway_sub}, %{1 => trinity_sub}), %{}, [])

    assert result.capway.active_subscribers["C-001"].email == nil
  end

  test "leaves email nil when payment processor errors" do
    set_responses(%{"CID-001" => {:error, :timeout}})

    capway_sub = build_capway(%{capway_customer_id: "CID-001"})
    trinity_sub = build_trinity(%{})

    {:ok, result} =
      FetchCapwayEmails.run(args(%{"C-001" => capway_sub}, %{1 => trinity_sub}), %{}, [])

    assert result.capway.active_subscribers["C-001"].email == nil
  end

  test "skips entries without capway_customer_id" do
    # Force the test to fail loudly if the client is called for a nil id —
    # the MockClient raises on unexpected calls if we put a sentinel.
    set_responses(%{})

    capway_sub = build_capway(%{capway_customer_id: nil})
    trinity_sub = build_trinity(%{})

    {:ok, result} =
      FetchCapwayEmails.run(args(%{"C-001" => capway_sub}, %{1 => trinity_sub}), %{}, [])

    assert result.capway.active_subscribers["C-001"].email == nil
  end

  test "skips entries whose trinity counterpart is capway_sync_excluded" do
    # If the client is called for an excluded sub, we'd see "wrong@example.com".
    set_responses(%{"CID-001" => {:ok, %{"email" => "wrong@example.com"}}})

    capway_sub = build_capway(%{capway_customer_id: "CID-001"})
    trinity_sub = build_trinity(%{capway_sync_excluded: true})

    {:ok, result} =
      FetchCapwayEmails.run(args(%{"C-001" => capway_sub}, %{1 => trinity_sub}), %{}, [])

    assert result.capway.active_subscribers["C-001"].email == nil
  end

  test "tolerates response shapes without an email field" do
    set_responses(%{"CID-001" => {:ok, %{"name" => "Alice"}}})

    capway_sub = build_capway(%{capway_customer_id: "CID-001"})
    trinity_sub = build_trinity(%{})

    {:ok, result} =
      FetchCapwayEmails.run(args(%{"C-001" => capway_sub}, %{1 => trinity_sub}), %{}, [])

    assert result.capway.active_subscribers["C-001"].email == nil
  end

  test "treats blank email strings as nil" do
    set_responses(%{"CID-001" => {:ok, %{"email" => ""}}})

    capway_sub = build_capway(%{capway_customer_id: "CID-001"})
    trinity_sub = build_trinity(%{})

    {:ok, result} =
      FetchCapwayEmails.run(args(%{"C-001" => capway_sub}, %{1 => trinity_sub}), %{}, [])

    assert result.capway.active_subscribers["C-001"].email == nil
  end

  test "fetches emails for many entries concurrently and merges all" do
    responses =
      for i <- 1..5, into: %{} do
        {"CID-#{i}", {:ok, %{"email" => "user#{i}@example.com"}}}
      end

    set_responses(responses)

    capway_active =
      for i <- 1..5, into: %{} do
        sub =
          build_capway(%{
            capway_customer_id: "CID-#{i}",
            national_id: "19640327381#{i}",
            trinity_subscriber_id: i,
            capway_contract_ref: "C-#{i}"
          })

        {"C-#{i}", sub}
      end

    trinity_active =
      for i <- 1..5, into: %{} do
        sub = build_trinity(%{trinity_subscriber_id: i, national_id: "19640327381#{i}"})
        {i, sub}
      end

    {:ok, result} = FetchCapwayEmails.run(args(capway_active, trinity_active), %{}, [])

    for i <- 1..5 do
      assert result.capway.active_subscribers["C-#{i}"].email == "user#{i}@example.com"
    end
  end
end
