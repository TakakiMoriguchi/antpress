defmodule AntPress.Storage.Supabase do
  @moduledoc """
  Supabase Storage に保存するアダプタ。**本番で使う。**

  Supabase は「マネージド PostgreSQL ＋ オブジェクトストレージ」としてのみ
  使う（Auth / PostgREST / Realtime は使わない → `docs/DECISIONS.md` 4.2）。
  そのため公式クライアントは入れず、**REST を `Req` で直接叩く**。

  ## 必要な設定

      config :antpress, :storage,
        adapter: AntPress.Storage.Supabase,
        url: "https://xxxx.supabase.co",
        service_role_key: "...",
        bucket: "antpress"

  ## ⚠️ バケットは public にする

  画像は HP の `<img src>` から読まれる。**ブラウザが直接取得できないと
  意味がない**ので、バケットは public にして
  `/storage/v1/object/public/{bucket}/{path}` で配信する。

  配信 API（`/api/v1/*`）は Bearer 認証必須で CORS も許可しない
  （→ `CLAUDE.md`）が、**画像は別**。混同しないこと。
  記事本文の HTML に埋まった画像を HP が表示できなくなる。

  パスに client_id が入るだけで秘匿性はない。URL は推測不能な UUID だが、
  **知られたら読める**前提で扱う。もともと公開 HP に載せる画像なので問題にならない。

  ## ⚠️ `service_role_key` はログに出さない

  このキーは RLS を無視して全バケットを操作できる。エラーを返すときも
  リクエストヘッダを含めない。
  """
  @behaviour AntPress.Storage

  alias AntPress.Storage

  @impl true
  def put(path, body, content_type) do
    # x-upsert: 同じパスがあれば上書きする（behaviour の契約）
    [
      method: :post,
      url: object_url(path),
      headers: [{"content-type", content_type}, {"x-upsert", "true"}],
      body: body
    ]
    |> request()
    |> handle_response()
  end

  @impl true
  def delete(path) do
    [method: :delete, url: object_url(path)]
    |> request()
    |> handle_response()
  end

  @impl true
  def public_url(path) do
    "#{base_url()}/storage/v1/object/public/#{bucket()}/#{encode_path(path)}"
  end

  defp object_url(path) do
    "#{base_url()}/storage/v1/object/#{bucket()}/#{encode_path(path)}"
  end

  defp request(opts) do
    # `plug` はテストで `Req.Test` を差し込むための穴。
    # 実際の Supabase に到達できない環境でもこのアダプタを検証できる
    test_opts =
      case Storage.config(:plug, nil) do
        nil -> []
        plug -> [plug: plug]
      end

    [auth: {:bearer, service_role_key()}, receive_timeout: 30_000, retry: false]
    |> Keyword.merge(opts)
    |> Keyword.merge(test_opts)
    |> Req.new()
    |> Req.request()
  end

  # ⚠️ エラーには status と本文だけを載せる。ヘッダ（=キー）は載せない
  defp handle_response({:ok, %Req.Response{status: status}}) when status in 200..299, do: :ok

  defp handle_response({:ok, %Req.Response{status: status, body: body}}) do
    {:error, {:supabase_storage, status, truncate(body)}}
  end

  defp handle_response({:error, reason}), do: {:error, {:supabase_storage, reason}}

  defp truncate(body) when is_binary(body), do: String.slice(body, 0, 500)
  defp truncate(body), do: body

  # パス要素は antpress が生成した UUID なので実際には変換されないが、
  # 区切りの "/" を保ったままエスケープしておく
  defp encode_path(path) do
    path
    |> String.split("/")
    |> Enum.map_join("/", &URI.encode_www_form/1)
  end

  defp base_url, do: Storage.config!(:url) |> String.trim_trailing("/")
  defp bucket, do: Storage.config(:bucket, "antpress")
  defp service_role_key, do: Storage.config!(:service_role_key)
end
