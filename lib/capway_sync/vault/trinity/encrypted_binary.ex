defmodule CapwaySync.Vault.Trinity.Encrypted.Binary do
  use Cloak.Ecto.Binary, vault: CapwaySync.Vault.Trinity.AES.GCM

  def equal?(term1, term2), do: term1 == term2
end
