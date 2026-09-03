defmodule AntPress.Encrypted.Binary do
  @moduledoc """
  暗号化して保存する文字列フィールド用の Ecto 型。

  DB のカラム型は `:binary` にする必要がある。
  """
  use Cloak.Ecto.Binary, vault: AntPress.Vault
end
