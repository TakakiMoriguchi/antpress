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

  ## ⚠️ `slug`（記事のアドレス）はシステムが決める。ユーザーは触れない

  作成時にランダムな文字列を割り当て、**以後変更できない。** 画面にも
  入力欄を出さない（→ `docs/DECISIONS.md` 3.2）。

  理由は 2 つ。

  1. **URL を変えないことが SEO 上いちばん重要。** URL 内の語がランキングに
     効く度合いはごく小さい一方、公開後に URL が変わると既存のリンクが
     404 になり、蓄積された評価も失われる。HP は SSG でリダイレクトを
     張る仕組みもない。**編集できなければこの事故は起きない**
  2. **想定ユーザー（店舗オーナー）に半角英字を考えさせない。**
     効果がほぼ無い項目のために入力を求めていた

  ⚠️ 代償: URL が意味を持たないので、共有されたときに内容が分からず、
  検索結果でのクリック率もわずかに落ちる。**1 の利益の方が大きいと判断した。**

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

    # 既定は `:published`。書いたらそのまま出したい方が普通で、
    # 下書きにしたい場合だけ切り替える
    field :status, Ecto.Enum, values: [:draft, :published], default: :published
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
    # ⚠️ `slug` は cast しない。システムが決める（→ モジュールの説明）
    |> cast(attrs, [
      :title,
      :body_format,
      :body,
      :category_id,
      :thumbnail_image_id,
      :status,
      :published_at
    ])
    |> put_slug()
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

  @doc """
  記事のアドレスに使うランダムな文字列を作る。

  Base32（小文字・パディングなし）の 13 文字 = 64 ビット。
  1 クライアント内で衝突する確率は無視できるが、万一に備えて
  `AntPress.Blog.create_article/2` が作り直す。

  **完全な UUID（36 文字）にしていない理由**: 記事の URL は LINE や SNS に
  貼られる。同じだけ推測不能でありながら短い方が実用的。
  """
  def generate_slug do
    8
    |> :crypto.strong_rand_bytes()
    |> Base.encode32(case: :lower, padding: false)
  end

  # ⚠️ **作成時のみ**割り当てる。既存の記事では絶対に振り直さない
  # （URL が変わると既存のリンクが 404 になる → モジュールの説明）
  defp put_slug(changeset) do
    case changeset.data.slug do
      nil -> put_change(changeset, :slug, generate_slug())
      _existing -> changeset
    end
  end

  # 生成しているので通常は必ず通るが、保険として残す。
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
