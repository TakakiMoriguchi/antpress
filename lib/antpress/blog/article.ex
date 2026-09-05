defmodule AntPress.Blog.Article do
  @moduledoc """
  ブログ記事。

  ## ⚠️ `body` は常に Markdown。`body_format` は「エディタのモード」

  Toast UI Editor は **WYSIWYG モードでも内部表現は Markdown** で、
  `getMarkdown()` はどちらのモードでも Markdown を返す。
  そのため保存形式は 1 つで、`body_format` は
  **次に開くときどちらのモードで開くか**の記録にすぎない。

  | `body_format` | Toast UI の `initialEditType` |
  | --- | --- |
  | `:rich_text`（**既定**） | `"wysiwyg"` |
  | `:markdown` | `"markdown"` |

  こうすると**モードを切り替えても本文が変換で劣化しない。**
  リッチテキスト側を HTML で保存すると、切り替えのたびに情報が落ちる。

  `body_html` は配信用にレンダリングした結果（→ `AntPress.Blog.Markdown`）。
  **キャッシュなので陳腐化する**（→ `docs/DATA-MODEL.md` 5.4）。

  ## 予約投稿に専用ステータスを作らない

  `status = :published` かつ `published_at` が未来。配信条件を
  `status = 'published' AND published_at <= now()` にするだけで成立する。

  ⚠️ 公開なのに `published_at` が null だと**永久に配信されない記事**に
  なるため、DB の CHECK 制約で禁止し、changeset でも現在時刻を補う。

  ## changeset を用途ごとに分けている

  * `changeset/3` — 基本プランの編集画面から使う
  * AI 生成用（`generation_status` など）は実装 9 で別に足す

  1 つの changeset で全部 cast すると、フォームに隠しフィールドを足すだけで
  `generation_status` や `published_notified_at` を書き換えられてしまう。
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias AntPress.Blog.{Category, Markdown}
  alias AntPress.Media.Image
  alias AntPress.Platform.Client

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "blog_articles" do
    field :title, :string

    # 記事 URL に使う。一意性はクライアント単位
    field :slug, :string

    # 既定は `:rich_text`（WYSIWYG）。Markdown は玄人向けで、
    # 想定ユーザー（店舗オーナー）は記法を知らない
    field :body_format, Ecto.Enum, values: [:rich_text, :markdown], default: :rich_text

    # 入力された Markdown
    field :body, :string
    # 配信用にレンダリング済みの HTML（保存時に body から生成）
    field :body_html, :string

    # ── AI プラン専用（実装 9）。基本プランでは触らない ──
    field :source_text, :string
    field :generation_status, Ecto.Enum, values: [:idle, :generating, :failed], default: :idle
    field :generation_error, :string

    field :status, Ecto.Enum, values: [:draft, :published], default: :draft
    field :published_at, :utc_datetime
    # Webhook 通知済みの時刻（実装 7）
    field :published_notified_at, :utc_datetime

    belongs_to :client, Client
    belongs_to :category, Category
    belongs_to :thumbnail_image, Image

    # ⚠️ マイクロ秒精度。一覧を updated_at 降順で並べるため
    # （→ マイグレーションの注記）
    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  記事の changeset。

  ⚠️ `client_id` は cast しない。スコープから設定する。

  ⚠️ `category_id` / `thumbnail_image_id` が**同じクライアントのものか**は
  ここでは検証できない（DB 参照が必要）。`AntPress.Blog` 側で検証している。
  """
  def changeset(article, attrs, client_scope) do
    article
    |> cast(attrs, [
      :title,
      :slug,
      :body_format,
      :body,
      :category_id,
      :thumbnail_image_id,
      :status,
      :published_at
    ])
    |> validate_required([:title, :slug])
    |> validate_length(:title, max: 120)
    |> validate_slug()
    |> put_body_html()
    |> put_published_at()
    |> unique_constraint([:client_id, :slug],
      name: :blog_articles_client_id_slug_index,
      message: "このアドレスは既に使われています"
    )
    |> foreign_key_constraint(:category_id)
    |> foreign_key_constraint(:thumbnail_image_id)
    |> check_constraint(:published_at,
      name: :blog_articles_published_requires_published_at,
      message: "公開する記事には公開日時が必要です"
    )
    |> put_client_id(client_scope)
  end

  # 記事 URL に使うので英小文字・数字・ハイフンのみ。
  # ⚠️ 画面では「スラッグ」と呼ばない。想定ユーザー（店舗オーナー）に
  #    通じない WordPress 用語なので「記事のアドレス」と表示する
  defp validate_slug(changeset) do
    changeset
    |> validate_length(:slug, min: 1, max: 80)
    |> validate_format(:slug, ~r/^[a-z0-9]+(-[a-z0-9]+)*$/,
      message: "半角の英字（小文字）・数字・ハイフンだけが使えます（先頭と末尾にハイフンは使えません）"
    )
  end

  # 本文が変わったときだけ再レンダリングする。
  # ⚠️ クライアントから送られた HTML は使わない。**サーバー側で生成する**
  #    （Toast UI の getHTML() を信用すると XSS の経路になる）
  defp put_body_html(changeset) do
    case fetch_change(changeset, :body) do
      {:ok, body} -> put_change(changeset, :body_html, Markdown.to_html(body))
      :error -> changeset
    end
  end

  # 公開に切り替えたが日時が空なら「今」にする。
  # 予約投稿したい場合はユーザーが未来の日時を入れる
  defp put_published_at(changeset) do
    case {get_field(changeset, :status), get_field(changeset, :published_at)} do
      {:published, nil} -> put_change(changeset, :published_at, DateTime.utc_now(:second))
      _ -> changeset
    end
  end

  # ⚠️ `client_id` は**作成時のみ**設定する（→ blog/category.ex に同じ注記）。
  defp put_client_id(changeset, client_scope) do
    case changeset.data.client_id do
      nil -> put_change(changeset, :client_id, client_scope.client.id)
      _existing -> changeset
    end
  end
end
