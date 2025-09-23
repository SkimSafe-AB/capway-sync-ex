defmodule CapwaySync.Dynamodb.Client do
  @behaviour CapwaySync.Dynamodb.Behaviour

  def start_link(_) do
    ExAws.Dynamo.start_link()
  end

  def put_item(table, item) do
    ExAws.Dynamo.put_item(table, item)
    |> ExAws.request()
  end

  def get_item(table, key) do
    ExAws.Dynamo.get_item(table, key)
    |> ExAws.request()
  end

  def delete_item(table, key) do
    ExAws.Dynamo.delete_item(table, key)
    |> ExAws.request()
  end
end
