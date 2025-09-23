defmodule CapwaySync.Vault.Trinity.AES.GCM do
  @moduledoc false
  use Cloak.Vault, otp_app: :capway_sync

  @impl GenServer
  def init(config) do
    if System.get_env("TRINITY_DB_VAULT_KEY") do
      ciphers = [
        default: {
          Cloak.Ciphers.AES.GCM,
          tag: aes_tag(), key: decode_env!("TRINITY_DB_VAULT_KEY")
        }
      ]

      retired_key = decode_env!("TRINITY_DB_VAULT_KEY_RETIRED")

      ciphers =
        if not is_nil(retired_key) and retired_key != "" do
          Keyword.put(ciphers, :retired, {
            Cloak.Ciphers.AES.GCM,
            tag: aes_tag(), key: retired_key
          })
        else
          ciphers
        end

      {:ok, Keyword.put(config, :ciphers, ciphers)}
    else
      {:ok, config}
    end
  end

  defp decode_env!(var) do
    var
    |> System.get_env()
    |> Base.decode64!()
  end

  defp aes_tag() do
    tag = "TRINITY_VAULT_TAG" |> System.get_env()
    IO.puts("ENV TAG: #{tag}")

    if is_nil(tag) or tag == "" do
      "AES.GCM.V1"
    else
      tag
    end
  end
end
