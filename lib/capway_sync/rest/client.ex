defmodule CapwaySync.Rest.Client do
  @moduledoc """
  Module to interact with Capway's REST API.
  """
  require Logger

  def return_result({:ok, %Req.Response{status: 200, body: body}}), do: {:ok, body}

  def return_result({:ok, %Req.Response{status: status, body: body}}) when status >= 400,
    do: {:error, {status, body}}

  def return_result({:error, reason}), do: {:error, reason}

  def set_std_headers do
    [
      {
        :accept,
        "application/json"
      },
      {
        :content_length,
        "0"
      }
    ]
  end

  def get_env(var) do
    Application.get_env(:capway_sync, :rest_api)[var] ||
      raise "#{var} is not set in :capway_sync, :rest_api"
  end
end
