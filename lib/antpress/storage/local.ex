defmodule AntPress.Storage.Local do
  @moduledoc """
  ローカルディスクに保存するアダプタ。**開発とテスト専用。**

  開発では `priv/static/uploads/` に置き、`/uploads/...` で配信する
  （`AntPressWeb.static_paths/0` に `uploads` を追加してある）。

  ⚠️ `priv/static/images/` は Phoenix の静的アセット置き場として
  既に使われている。アップロード先は `uploads` にして混ざらないようにする。

  本番では使わない。Fly.io のインスタンスはファイルシステムが揮発するため。
  """
  @behaviour AntPress.Storage

  alias AntPress.Storage

  @impl true
  def put(path, body, _content_type) do
    full = full_path(path)

    with :ok <- File.mkdir_p(Path.dirname(full)) do
      File.write(full, body)
    end
  end

  @impl true
  def delete(path) do
    case File.rm(full_path(path)) do
      :ok -> :ok
      # 既に無いのは削除の目的が達成されている状態なので成功扱いにする
      {:error, :enoent} -> :ok
      other -> other
    end
  end

  @impl true
  def public_url(path) do
    Storage.config(:url_prefix, "/uploads") <> "/" <> path
  end

  defp full_path(path), do: Path.join(root(), path)

  defp root, do: Storage.config(:root, Path.join(["priv", "static", "uploads"]))
end
