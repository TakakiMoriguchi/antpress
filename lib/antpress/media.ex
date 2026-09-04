defmodule AntPress.Media do
  @moduledoc """
  画像（クライアントがアップロードした素材）のコンテキスト。

  ## なぜ `Blog` に入れず独立させたか

  `docs/DATA-MODEL.md` 1.5 は「スキーマ 1 つのコンテキストは切らない」と
  している。`Media` は `Image` 1 つしか持たないので**その例外**にあたる。
  理由は 2 つ。

  1. **テーブル名が `blog_images` ではなく `images`。** 画像はブログ専有では
     なく、クライアントの素材置き場。`Blog` に入れると、将来 EC などで
     同じ画像を使いたくなったときに移動が要る（→ `DECISIONS.md` 3.9 将来検討）
  2. **持っている責務がコンテンツのモデリングではない。**
     オブジェクトストレージへの書き込み・削除、MIME とサイズの検証、
     ヘッダからの縦横サイズ取得。これを `Blog` に混ぜると、記事の
     ドメインロジックにファイル I/O が同居する

  ファイル本体の保存先は `AntPress.Storage` が抽象化している。

  ## 失敗したときにどちらへ倒すか

  DB とストレージは別系統なので、**片方だけ成功する**ことがありうる。
  そのとき残す状態を意図的に選んでいる。

  | 操作 | 順序 | 片方失敗したときに残るもの |
  | --- | --- | --- |
  | 作成 | ストレージ → DB | DB 失敗時は**ストレージを消してから**返す |
  | 削除 | DB → ストレージ | ストレージ失敗時は**孤児オブジェクト**が残る |

  どちらも「**参照先が無いレコードを作らない**」side に倒している。
  孤児オブジェクトは容量を無駄にするだけだが、実体の無いレコードは
  HP 上で画像が壊れて見える。問い合わせを DB 保存優先にしているのと同じ考え方
  （→ `docs/DECISIONS.md` 3.4）。
  """

  import Ecto.Query, warn: false
  require Logger

  alias AntPress.Repo
  alias AntPress.Storage
  alias AntPress.Media.{Image, Probe}
  alias AntPress.Accounts.Scope

  @doc """
  Subscribes to scoped notifications about any image changes.

  The broadcasted messages match the pattern:

    * {:created, %Image{}}
    * {:updated, %Image{}}
    * {:deleted, %Image{}}

  """
  def subscribe_images(%Scope{} = scope) do
    Phoenix.PubSub.subscribe(AntPress.PubSub, topic(scope))
  end

  defp broadcast_image(%Scope{} = scope, message) do
    Phoenix.PubSub.broadcast(AntPress.PubSub, topic(scope), message)
  end

  defp topic(%Scope{} = scope), do: "client:#{scope.client.id}:images"

  @doc """
  クライアントの画像一覧。新しいものが先。
  """
  def list_images(%Scope{} = scope) do
    Image
    |> where(client_id: ^scope.client.id)
    |> order_by(desc: :inserted_at, desc: :id)
    |> Repo.all()
  end

  @doc """
  画像を 1 件取得する。他クライアントの画像は取れない。
  """
  def get_image!(%Scope{} = scope, id) do
    Repo.get_by!(Image, id: id, client_id: scope.client.id)
  end

  @doc """
  画像をアップロードする。

  `attrs` は `%{filename: ..., body: <バイナリ>}`。任意で `alt_text`。

  ## ⚠️ `content_type` は受け取らない。バイナリから判定する

  ブラウザの申告（`entry.client_type`）もファイル名の拡張子も使わず、
  先頭バイトから形式を決める（→ `AntPress.Media.Probe`）。
  拡張子と中身が食い違ったファイルを保存しないため。

  ## 戻り値

    * `{:ok, %Image{}}`
    * `{:error, :unsupported_format}` — 対応形式と判定できなかった
    * `{:error, %Ecto.Changeset{}}` — サイズなどが不正
    * `{:error, {:storage, reason}}` — ストレージへの書き込みに失敗

  ## 検証はアップロードの前に行う

  上限超過のファイルをストレージに書いてから弾く、という順序にはしない。
  """
  def create_image(%Scope{} = scope, %{body: body} = attrs) when is_binary(body) do
    case Probe.content_type(body) do
      nil ->
        {:error, :unsupported_format}

      content_type ->
        storage_path = build_storage_path(scope, content_type)
        {width, height} = dimensions(body)

        row = %{
          storage_path: storage_path,
          filename: Map.get(attrs, :filename),
          content_type: content_type,
          byte_size: byte_size(body),
          width: width,
          height: height,
          alt_text: Map.get(attrs, :alt_text)
        }

        changeset = Image.create_changeset(%Image{}, row, scope)

        # ⚠️ 先に検証する。ストレージに書いてから弾くと孤児が出る
        if changeset.valid? do
          upload_then_insert(scope, changeset, storage_path, body, content_type)
        else
          {:error, apply_action_error(changeset)}
        end
    end
  end

  defp upload_then_insert(scope, changeset, storage_path, body, content_type) do
    case Storage.put(storage_path, body, content_type) do
      :ok ->
        case Repo.insert(changeset) do
          {:ok, %Image{} = image} ->
            broadcast_image(scope, {:created, image})
            {:ok, image}

          {:error, changeset} ->
            # DB に入らなかったオブジェクトは残さない
            _ = Storage.delete(storage_path)
            {:error, changeset}
        end

      {:error, reason} ->
        Logger.error("画像のアップロードに失敗しました path=#{storage_path} reason=#{inspect(reason)}")
        {:error, {:storage, reason}}
    end
  end

  @doc """
  代替テキストを更新する。**画面から変更できるのはここだけ。**
  """
  def update_image(%Scope{} = scope, %Image{} = image, attrs) do
    true = image.client_id == scope.client.id

    with {:ok, %Image{} = image} <-
           image
           |> Image.alt_text_changeset(attrs)
           |> Repo.update() do
      broadcast_image(scope, {:updated, image})
      {:ok, image}
    end
  end

  @doc """
  画像を削除する。DB のレコードを消してから本体を消す（→ モジュールの説明）。

  本体の削除に失敗してもエラーにはしない。**ログに残して先に進む。**
  ここで失敗を返すと、レコードは既に消えているのに画面がエラーになり、
  ユーザーには再試行のしようがない。
  """
  def delete_image(%Scope{} = scope, %Image{} = image) do
    true = image.client_id == scope.client.id

    with {:ok, %Image{} = image} <- Repo.delete(image) do
      case Storage.delete(image.storage_path) do
        :ok ->
          :ok

        {:error, reason} ->
          Logger.error(
            "画像レコードは削除しましたが本体が残りました path=#{image.storage_path} reason=#{inspect(reason)}"
          )
      end

      broadcast_image(scope, {:deleted, image})
      {:ok, image}
    end
  end

  @doc """
  HP の `<img src>` から参照できる URL。
  """
  def public_url(%Image{} = image), do: Storage.public_url(image.storage_path)

  @doc """
  代替テキスト編集フォーム用の changeset。
  """
  def change_image(%Scope{} = scope, %Image{} = image, attrs \\ %{}) do
    true = image.client_id == scope.client.id

    Image.alt_text_changeset(image, attrs)
  end

  # `clients/{client_id}/{uuid}.{ext}` にしてテナントごとに分ける。
  # 拡張子は判定した content_type から決める（ファイル名は信用しない）
  defp build_storage_path(%Scope{} = scope, content_type) do
    ext = Image.extension_for(content_type) || "bin"
    "clients/#{scope.client.id}/#{Ecto.UUID.generate()}.#{ext}"
  end

  defp dimensions(body) do
    case Probe.size(body) do
      {w, h} -> {w, h}
      nil -> {nil, nil}
    end
  end

  # `valid?: false` の changeset をそのまま返すと、フォームに繋いだときに
  # エラーが表示されない（action が nil のため）。
  defp apply_action_error(changeset), do: Map.put(changeset, :action, :insert)
end
