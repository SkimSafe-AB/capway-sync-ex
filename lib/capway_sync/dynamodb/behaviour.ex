defmodule CapwaySync.Dynamodb.Behaviour do
  @moduledoc """
  Behaviour for DynamoDB operations in the CapwaySync application.

  Defines the contract for DynamoDB client implementations to ensure
  consistent interface across different environments and testing scenarios.
  """

  @doc """
  Starts the DynamoDB client process.
  """
  @callback start_link(term()) :: {:ok, pid()} | {:error, term()}

  @doc """
  Puts an item into the specified DynamoDB table.

  ## Parameters
  - `table`: The name of the DynamoDB table
  - `item`: The item to store (typically a map)

  ## Returns
  - `{:ok, result}` on success
  - `{:error, reason}` on failure
  """
  @callback put_item(String.t(), map()) :: {:ok, term()} | {:error, term()}

  @doc """
  Gets an item from the specified DynamoDB table using the provided key.

  ## Parameters
  - `table`: The name of the DynamoDB table
  - `key`: The key to look up (typically a map with partition key and optional sort key)

  ## Returns
  - `{:ok, result}` on success (result may be empty if item not found)
  - `{:error, reason}` on failure
  """
  @callback get_item(String.t(), map()) :: {:ok, term()} | {:error, term()}

  @doc """
  Deletes an item from the specified DynamoDB table using the provided key.

  ## Parameters
  - `table`: The name of the DynamoDB table
  - `key`: The key of the item to delete

  ## Returns
  - `{:ok, result}` on success
  - `{:error, reason}` on failure
  """
  @callback delete_item(String.t(), map()) :: {:ok, term()} | {:error, term()}
end