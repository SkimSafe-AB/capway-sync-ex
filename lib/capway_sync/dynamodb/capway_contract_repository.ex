defmodule CapwaySync.Dynamodb.CapwayContractRepository do
  @moduledoc """
  Repository for storing Capway contract data at the contract level in DynamoDB.

  Each contract is stored as its own item with `contract_ref_no` as the primary key.
  This provides fast lookups by contract without hitting the slow Capway SOAP API.

  ## Table Schema

  - Partition key: `contract_ref_no` (String)
  - All Capway subscriber fields stored as top-level attributes
  - `updated_at` timestamp for staleness tracking

  ## Configuration

  - `CAPWAY_CONTRACTS_TABLE` env var for table name (default: "capway-contracts")
  """

  alias CapwaySync.Dynamodb.Client
  alias CapwaySync.Models.CapwaySubscriber

  require Logger

  @table_name_env "CAPWAY_CONTRACTS_TABLE"
  @default_table_name "capway-contracts"

  @doc """
  Stores a single Capway contract in DynamoDB.
  """
  @spec store_contract(%CapwaySubscriber{}) :: :ok | {:error, term()}
  def store_contract(%CapwaySubscriber{contract_ref_no: nil}) do
    Logger.warning("Skipping contract with nil contract_ref_no")
    :ok
  end

  def store_contract(%CapwaySubscriber{} = subscriber) do
    item = serialize(subscriber)

    case Client.put_item(table_name(), item) do
      {:ok, _} -> :ok
      {:error, reason} ->
        Logger.error(
          "Failed to store contract #{subscriber.contract_ref_no}: #{inspect(reason)}"
        )

        {:error, reason}
    end
  end

  @doc """
  Stores a list of Capway contracts in DynamoDB.

  Skips contracts without a `contract_ref_no`. Returns `{stored_count, error_count}`.
  """
  @spec store_contracts([%CapwaySubscriber{}]) :: {non_neg_integer(), non_neg_integer()}
  def store_contracts(subscribers) when is_list(subscribers) do
    subscribers
    |> Enum.reduce({0, 0}, fn subscriber, {ok_count, err_count} ->
      case store_contract(subscriber) do
        :ok -> {ok_count + 1, err_count}
        {:error, _} -> {ok_count, err_count + 1}
      end
    end)
  end

  @doc """
  Retrieves a contract by its contract reference number.
  """
  @spec get_contract(String.t()) :: {:ok, %CapwaySubscriber{}} | {:not_found} | {:error, term()}
  def get_contract(contract_ref_no) do
    case Client.get_item(table_name(), %{"contract_ref_no" => contract_ref_no}) do
      {:ok, %{"Item" => item}} ->
        {:ok, deserialize(item)}

      {:ok, %{}} ->
        {:not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Retrieves all contracts for a given customer reference (Capway customer ID).

  Uses a query on the `customer_ref-index` GSI.
  """
  @spec get_contracts_by_customer_ref(String.t()) ::
          {:ok, [%CapwaySubscriber{}]} | {:error, term()}
  def get_contracts_by_customer_ref(customer_ref) do
    opts = [
      index_name: "customer_ref-index",
      key_condition_expression: "customer_ref = :cr",
      expression_attribute_values: %{":cr" => customer_ref}
    ]

    case Client.query(table_name(), opts) do
      {:ok, %{"Items" => items}} ->
        {:ok, Enum.map(items, &deserialize/1)}

      {:ok, %{}} ->
        {:ok, []}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Retrieves all contracts for a given national ID (personal number).

  Uses a query on the `id_number-index` GSI.
  """
  @spec get_contracts_by_national_id(String.t()) ::
          {:ok, [%CapwaySubscriber{}]} | {:error, term()}
  def get_contracts_by_national_id(id_number) do
    opts = [
      index_name: "id_number-index",
      key_condition_expression: "id_number = :id",
      expression_attribute_values: %{":id" => id_number}
    ]

    case Client.query(table_name(), opts) do
      {:ok, %{"Items" => items}} ->
        {:ok, Enum.map(items, &deserialize/1)}

      {:ok, %{}} ->
        {:ok, []}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Serializes a `%CapwaySubscriber{}` to a DynamoDB item map.
  """
  @spec serialize(%CapwaySubscriber{}) :: map()
  def serialize(%CapwaySubscriber{} = subscriber) do
    %{
      "contract_ref_no" => subscriber.contract_ref_no,
      "customer_id" => subscriber.customer_id,
      "contract_price" => subscriber.contract_price,
      "next_invoice_date" => subscriber.next_invoice_date,
      "customer_ref" => subscriber.customer_ref,
      "id_number" => subscriber.id_number,
      "name" => subscriber.name,
      "reg_date" => subscriber.reg_date,
      "start_date" => subscriber.start_date,
      "end_date" => subscriber.end_date,
      "active" => subscriber.active,
      "paid_invoices" => subscriber.paid_invoices,
      "unpaid_invoices" => subscriber.unpaid_invoices,
      "collection" => subscriber.collection,
      "last_invoice_status" => subscriber.last_invoice_status,
      "updated_at" => DateTime.utc_now() |> DateTime.to_iso8601()
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  @doc """
  Deserializes a DynamoDB item map back to a `%CapwaySubscriber{}`.
  """
  @spec deserialize(map()) :: %CapwaySubscriber{}
  def deserialize(item) when is_map(item) do
    %CapwaySubscriber{
      contract_ref_no: get_value(item, "contract_ref_no"),
      customer_ref: get_value(item, "customer_ref"),
      id_number: get_value(item, "id_number"),
      name: get_value(item, "name"),
      reg_date: get_value(item, "reg_date"),
      start_date: get_value(item, "start_date"),
      end_date: get_value(item, "end_date"),
      active: get_value(item, "active"),
      paid_invoices: get_value(item, "paid_invoices"),
      unpaid_invoices: get_value(item, "unpaid_invoices"),
      collection: get_value(item, "collection"),
      last_invoice_status: get_value(item, "last_invoice_status"),
      customer_id: get_value(item, "customer_id"),
      contract_price: get_value(item, "contract_price"),
      next_invoice_date: get_value(item, "next_invoice_date"),
      origin: :capway,
      capway_id: get_value(item, "customer_ref"),
      trinity_id: nil,
      raw_data: nil
    }
  end

  # DynamoDB returns typed values like %{"S" => "val"} or %{"N" => "123"}
  # but ExAws may also return plain values depending on decode settings.
  defp get_value(item, key) do
    case Map.get(item, key) do
      %{"S" => val} -> val
      %{"N" => val} -> val
      %{"NULL" => true} -> nil
      val -> val
    end
  end

  defp table_name do
    System.get_env(@table_name_env, @default_table_name)
  end
end
