defmodule CapwaySync.Vault.Hashed.HMAC do
  @moduledoc """
  HMAC configuration for hashing sensitive data in CapwaySync.
  Uses SHA-512 algorithm with secret key from environment variable.
  """
  use Cloak.Ecto.HMAC, otp_app: :capway_sync

  @impl Cloak.Ecto.HMAC
  def init(config) do
    config =
      Keyword.merge(config,
        algorithm: :sha512,
        secret: System.get_env("CLOAK_HASHED_HMAC")
      )

    {:ok, config}
  end

  def embed_as(_format), do: :self

  def equal?(term1, term2), do: term1 == term2

  @doc """
  Hash a value using HMAC with the configured algorithm and secret.
  Returns base64 encoded hash.
  """
  def hash(value) do
    # Get the configuration
    {:ok, config} = init([])

    # Use :crypto.mac to generate HMAC
    algorithm = Keyword.get(config, :algorithm, :sha512)
    secret = Keyword.get(config, :secret)

    if secret do
      :crypto.mac(:hmac, algorithm, secret, value)
      |> Base.encode64()
    else
      raise "CLOAK_HASHED_HMAC environment variable not set"
    end
  end
end
