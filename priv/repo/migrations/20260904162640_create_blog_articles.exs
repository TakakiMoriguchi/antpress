defmodule AntPress.Repo.Migrations.CreateBlogArticles do
  use Ecto.Migration

  def change do
    create table(:blog_articles, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :client_id, references(:clients, type: :binary_id, on_delete: :delete_all), null: false

      add :title, :string, null: false
      add :slug, :string, null: false

      # ⚠️ body は **常に Markdown**。body_format はエディタをどちらの
      #    モードで開くかの記録（Toast UI Editor は WYSIWYG でも
      #    Markdown を保持する → lib/antpress/blog/article.ex）
      add :body_format, :string, null: false, default: "markdown"
      add :body, :text
      # 配信用にレンダリング済みの HTML。**キャッシュなので陳腐化する**
      add :body_html, :text

      # AI プラン専用（実装 9）。基本プランでは使わない
      add :source_text, :text
      add :generation_status, :string, null: false, default: "idle"
      add :generation_error, :text

      # カテゴリを消しても記事は残す（未分類になる）
      add :category_id, references(:blog_categories, type: :binary_id, on_delete: :nilify_all)

      # ⚠️ nilify_all にしないと、画像の削除が FK 違反で失敗する。
      #    画像を消したらサムネイルが外れる（画面の確認文で予告している）
      add :thumbnail_image_id, references(:images, type: :binary_id, on_delete: :nilify_all)

      add :status, :string, null: false, default: "draft"
      # 未来日時なら予約投稿。専用ステータスは作らない
      add :published_at, :utc_datetime
      # Webhook 通知済みの時刻（実装 7）。null が再送対象
      add :published_notified_at, :utc_datetime

      # ⚠️ **マイクロ秒**にする（images と同じ理由）。
      #
      # 一覧は updated_at の降順で並べる（→ docs/SCREENS.md C3）。
      # 秒精度だと同一秒に保存された記事が同着になり、第 2 キー
      # （id = ランダムな UUID）で順序が決まってしまう。
      # 「保存したのに一覧の先頭に来ない」という見え方になる。
      timestamps(type: :utc_datetime_usec)
    end

    # 配信 API の主クエリ: status = 'published' AND published_at <= now()
    create index(:blog_articles, [:client_id, :status, "published_at DESC"])

    # スラッグ解決・重複防止。グローバル一意にはしない
    create unique_index(:blog_articles, [:client_id, :slug])

    # Webhook 通知対象の抽出（部分索引）
    create index(:blog_articles, [:status, :published_at],
             where: "published_notified_at IS NULL",
             name: :blog_articles_pending_notification_index
           )

    # FK の索引。on_delete: :nilify_all の際に全走査させないため
    create index(:blog_articles, [:category_id])
    create index(:blog_articles, [:thumbnail_image_id])

    # Ecto.Enum に加えて DB 側でも値を絞る
    create constraint(:blog_articles, :blog_articles_body_format_must_be_valid,
             check: "body_format IN ('rich_text', 'markdown')"
           )

    create constraint(:blog_articles, :blog_articles_status_must_be_valid,
             check: "status IN ('draft', 'published')"
           )

    create constraint(:blog_articles, :blog_articles_generation_status_must_be_valid,
             check: "generation_status IN ('idle', 'generating', 'failed')"
           )

    # ⚠️ 公開なのに published_at が null だと、配信条件
    #    （published_at <= now()）に永久に一致せず**表示されない記事**になる。
    #    気付きにくい沈黙バグなので DB で禁止する
    create constraint(:blog_articles, :blog_articles_published_requires_published_at,
             check: "status <> 'published' OR published_at IS NOT NULL"
           )
  end
end
