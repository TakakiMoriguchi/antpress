defmodule AntPressWeb.EditorImageController do
  @moduledoc """
  記事本文に画像を挿入するためのアップロード口。

  Toast UI Editor の `addImageBlobHook` から呼ばれる。

  ## なぜ LiveView ではなくコントローラなのか

  エディタは JS が管理する領域（`phx-update="ignore"`）にあり、
  ファイルは JS が握った `Blob` として渡される。LiveView の
  `allow_upload` はフォームの `live_file_input` を前提にするため噛み合わない。

  `controllers/` を使うのは **Cookie を書くもの**と **JSON API** だけ
  （→ `CLAUDE.md`）。これは後者。

  ## ⚠️ 用意しないと base64 が本文に埋め込まれる

  Toast UI は `addImageBlobHook` を渡さないと画像を **data URI** にして
  Markdown に埋める。数百 KB の base64 が `body` と `body_html` に入り、
  記事も配信 API のレスポンスも肥大する。これを避けるための必須の口。

  ## 認証

  ブラウザのパイプラインを通すのでセッション認証＋CSRF 検証が効く。
  `require_authenticated_user` の下に置いてあるので、ログインしていない
  リクエストはここまで来ない。スコープは `conn.assigns.current_user`
  （＝クライアントスコープ）から取るので、**他クライアント配下には保存できない。**
  """
  use AntPressWeb, :controller

  alias AntPress.Media
  alias AntPressWeb.MediaError

  def create(conn, %{"file" => %Plug.Upload{} = upload}) do
    scope = conn.assigns.current_user

    case File.read(upload.path) do
      {:ok, body} ->
        # ⚠️ upload.content_type（ブラウザ申告）は渡さない。
        #    Media 側がバイナリから判定する
        scope
        |> Media.create_image(%{filename: upload.filename, body: body})
        |> respond(conn)

      {:error, reason} ->
        error(conn, 400, "ファイルを読み取れませんでした（#{inspect(reason)}）")
    end
  end

  def create(conn, _params), do: error(conn, 400, "ファイルが送信されていません")

  defp respond({:ok, image}, conn) do
    json(conn, %{url: Media.public_url(image), altText: image.alt_text || image.filename})
  end

  defp respond({:error, :unsupported_format = reason}, conn) do
    error(conn, 422, MediaError.message(reason))
  end

  # ストレージ側の障害なので 5xx。クライアントが再試行してよい
  defp respond({:error, {:storage, _} = reason}, conn) do
    error(conn, 502, MediaError.message(reason))
  end

  defp respond({:error, %Ecto.Changeset{} = changeset}, conn) do
    error(conn, 422, MediaError.message(changeset))
  end

  defp error(conn, status, message) do
    conn |> put_status(status) |> json(%{error: message})
  end
end
