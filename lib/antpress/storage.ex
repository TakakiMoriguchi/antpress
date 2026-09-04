defmodule AntPress.Storage do
  @moduledoc """
  画像本体（オブジェクト）の保存先を抽象化する層。

  本番は Supabase Storage、開発とテストはローカルディスクを使う
  （→ `AntPress.Storage.Local` / `AntPress.Storage.Supabase`）。

  ## なぜ差し替え可能にしているか

  ここはドメインではなく**インフラ**なので、`lib/antpress/` の直下に
  `Mailer` や `Vault` と並べて置いている。

  差し替えを用意した理由は 2 つ。

  1. **テストをネットワークに依存させない。** 画像アップロードのテストが
     Supabase に到達できるかどうかで落ちるようにはしない
  2. **Supabase の認証情報が無くても開発できる。** `SUPABASE_URL` を
     設定していない環境ではローカルディスクに保存する

  ## パスの形

  `clients/{client_id}/{uuid}.{ext}` にしてテナントごとに分ける
  （→ `docs/DATA-MODEL.md` 3.9）。パスは antpress 側が生成し、
  **アップロード時のファイル名は使わない**。日本語ファイル名や
  ディレクトリトラバーサルを構造的に排除できる。
  """

  @doc "オブジェクトを保存する。同じパスがあれば上書きする"
  @callback put(path :: String.t(), body :: binary(), content_type :: String.t()) ::
              :ok | {:error, term()}

  @doc "オブジェクトを削除する。存在しない場合も `:ok` を返す（冪等）"
  @callback delete(path :: String.t()) :: :ok | {:error, term()}

  @doc "HP の `<img src>` から参照できる URL を返す"
  @callback public_url(path :: String.t()) :: String.t()

  def put(path, body, content_type) do
    with :ok <- validate_path(path) do
      adapter().put(path, body, content_type)
    end
  end

  def delete(path) do
    with :ok <- validate_path(path) do
      adapter().delete(path)
    end
  end

  def public_url(path), do: adapter().public_url(path)

  @doc """
  現在のアダプタ。

  設定は `config :antpress, :storage, adapter: ..., ...` の形で持つ。
  アダプタ固有のオプションも同じキーワードリストに入れる。
  """
  def adapter, do: Keyword.fetch!(config(), :adapter)

  def config, do: Application.fetch_env!(:antpress, :storage)

  def config(key, default), do: Keyword.get(config(), key, default)

  def config!(key), do: Keyword.fetch!(config(), key)

  # パスは antpress が生成するので通常ここは通らないが、
  # ストレージへの書き込みは影響が大きいので二重に防ぐ。
  defp validate_path(path) when is_binary(path) do
    cond do
      path == "" -> {:error, :invalid_path}
      String.contains?(path, "..") -> {:error, :invalid_path}
      String.starts_with?(path, "/") -> {:error, :invalid_path}
      true -> :ok
    end
  end
end
