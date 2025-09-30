defmodule CapwaySync.Rest.AccessToken do
  alias CapwaySync.Rest.Client

  def run do
    api_url = "#{Client.get_env(:base_url)}/login/oauth/access_token"
    basic_auth = "#{Client.get_env(:username)}:#{Client.get_env(:password)}"

    req =
      Req.post(api_url,
        auth: {:basic, basic_auth},
        headers: Client.set_std_headers()
      )
      |> Client.return_result()

    case req do
      {:ok, %{"access_token" => token}} -> {:ok, token}
      {:error, reason} -> {:error, reason}
    end
  end
end
