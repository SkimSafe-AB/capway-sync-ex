defmodule CapwaySync.Vault.Trinity.AES.GCM do
  @moduledoc false
  use Cloak.Vault, otp_app: :capway_sync

  @impl GenServer
  def init(config) do
    default_cipher = [
      default: {
        Cloak.Ciphers.AES.GCM,
        tag: aes_tag(), key: decode_env!("TRINITY_DB_VAULT_KEY"), iv_length: iv_length()
      }
    ]

    retired_key = decode_env!("TRINITY_DB_VAULT_KEY_RETIRED")

    ciphers =
      if not is_nil(retired_key) and retired_key != "" do
        default_cipher ++
          [
            retired: {
              Cloak.Ciphers.AES.GCM,
              tag: aes_tag_retired(), key: retired_key, iv_length: iv_length_retired()
            }
          ]
      else
        default_cipher
      end

    IO.inspect(ciphers, label: "Vault Ciphers Configured")
    {:ok, Keyword.put(config, :ciphers, ciphers)}
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

  defp aes_tag_retired() do
    tag = "TRINITY_VAULT_TAG_RETIRED" |> System.get_env()
    IO.puts("ENV TAG RETIRED: #{tag}")

    if is_nil(tag) or tag == "" do
      "AES.GCM.V1"
    else
      tag
    end
  end

  defp iv_length() do
    length = "TRINITY_VAULT_IV_LENGTH" |> System.get_env()

    if is_nil(length) or length == "" do
      # Default IV length for AES.GCM
      12
    else
      String.to_integer(length)
    end
  end

  defp iv_length_retired() do
    length = "TRINITY_VAULT_IV_LENGTH_RETIRED" |> System.get_env()

    if is_nil(length) or length == "" do
      # Default IV length for AES.GCM
      12
    else
      String.to_integer(length)
    end
  end
end
