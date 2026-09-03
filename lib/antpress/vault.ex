defmodule AntPress.Vault do
  @moduledoc """
  developer の Anthropic API キーを暗号化するための Cloak Vault。

  ## なぜハッシュではなく暗号化なのか

  antpress が扱うキーは 2 種類あり、保存方法が異なる。

  | キー | 保存方法 | 理由 |
  | --- | --- | --- |
  | `api_keys.key_hash`（antpress の配信キー） | ハッシュ（SHA-256） | 検証するだけなので不可逆でよい |
  | `developers.anthropic_api_key` | **暗号化（可逆）** | Claude API を叩くのに平文が必要 |

  ## 鍵の扱い

  暗号鍵は環境変数 `CLOAK_KEY` から読む（本番）。DB には置かない。
  **この鍵が漏れると全 developer の Anthropic キーが復号可能になる。**
  """
  use Cloak.Vault, otp_app: :antpress
end
