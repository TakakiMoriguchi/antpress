defmodule AntPress.Blog.ArticleTest do
  @moduledoc """
  記事の context 層のテスト。**テナント越えの参照**を重点的に見る。
  """
  use AntPress.DataCase

  import AntPress.AccountsFixtures
  import AntPress.BlogFixtures
  import AntPress.MediaFixtures

  alias AntPress.Blog
  alias AntPress.Blog.Article
  alias AntPress.Accounts.Scope
  alias AntPress.Media

  setup do
    user = user_fixture()
    %{scope: Scope.for_user(user)}
  end

  describe "create_article/2" do
    test "記事を作成する", %{scope: scope} do
      assert {:ok, %Article{} = article} =
               Blog.create_article(scope, %{
                 title: "新メニューのお知らせ",
                 slug: "new-menu",
                 body: "# 見出し\n\n本文です。"
               })

      assert article.client_id == scope.client.id
      assert article.status == :draft
      assert article.body_format == :markdown
      assert article.generation_status == :idle
    end

    test "body から body_html をサーバー側で生成する", %{scope: scope} do
      article = article_fixture(scope, %{body: "# 見出し\n\n**太字**"})

      assert article.body_html =~ "<h1>見出し</h1>"
      assert article.body_html =~ "<strong>太字</strong>"
    end

    test "⚠️ 本文に書かれた生 HTML は通さない", %{scope: scope} do
      article =
        article_fixture(scope, %{
          body:
            "本文\n\n<script>alert(document.cookie)</script>\n\n<img src=x onerror=\"alert(1)\">"
        })

      refute article.body_html =~ "<script"
      refute article.body_html =~ "onerror"
      assert article.body_html =~ "raw HTML omitted"
    end

    test "表・打ち消し線・チェックリストが崩れない", %{scope: scope} do
      article =
        article_fixture(scope, %{
          body: "| 品目 | 値段 |\n| --- | --- |\n| ラーメン | 800円 |\n\n~~取消~~\n\n- [x] 済"
        })

      assert article.body_html =~ "<table>"
      assert article.body_html =~ "<del>取消</del>"
      assert article.body_html =~ ~s(type="checkbox")
    end

    test "本文が空でも作成できる（下書き）", %{scope: scope} do
      assert {:ok, article} = Blog.create_article(scope, %{title: "書きかけ", slug: "wip"})

      assert article.body == nil
      assert article.body_html == nil
    end

    test "タイトルとスラッグは必須", %{scope: scope} do
      assert {:error, changeset} = Blog.create_article(scope, %{})

      assert "can't be blank" in errors_on(changeset).title
      assert "can't be blank" in errors_on(changeset).slug
    end

    test "スラッグの形式を検証する", %{scope: scope} do
      assert {:error, changeset} = Blog.create_article(scope, %{title: "題", slug: "日本語"})

      assert errors_on(changeset).slug != []
    end

    test "スラッグはクライアント単位で一意", %{scope: scope} do
      article_fixture(scope, %{slug: "duplicated"})

      assert {:error, changeset} =
               Blog.create_article(scope, %{title: "別記事", slug: "duplicated"})

      assert "このスラッグは既に使われています" in errors_on(changeset).client_id
    end

    test "別クライアントなら同じスラッグを使える", %{scope: scope} do
      article_fixture(scope, %{slug: "news"})
      other_scope = Scope.for_user(user_fixture())

      assert {:ok, _} = Blog.create_article(other_scope, %{title: "題", slug: "news"})
    end

    test "公開にすると published_at が入る", %{scope: scope} do
      assert {:ok, article} =
               Blog.create_article(scope, %{title: "題", slug: "s", status: :published})

      assert article.published_at != nil
      assert DateTime.diff(DateTime.utc_now(), article.published_at) < 5
    end

    test "未来の published_at を指定すると予約投稿になる", %{scope: scope} do
      future = DateTime.add(DateTime.utc_now(:second), 3600, :second)

      assert {:ok, article} =
               Blog.create_article(scope, %{
                 title: "題",
                 slug: "s",
                 status: :published,
                 published_at: future
               })

      assert article.status == :published
      assert DateTime.after?(article.published_at, DateTime.utc_now())
    end
  end

  describe "⚠️ テナント越えの参照" do
    test "他クライアントのカテゴリは指定できない", %{scope: scope} do
      other_category = category_fixture(Scope.for_user(user_fixture()))

      assert {:error, changeset} =
               Blog.create_article(scope, %{
                 title: "題",
                 slug: "s",
                 category_id: other_category.id
               })

      assert "選べないカテゴリです" in errors_on(changeset).category_id
    end

    test "他クライアントの画像はサムネイルに指定できない", %{scope: scope} do
      other_image = image_fixture(Scope.for_user(user_fixture()))

      assert {:error, changeset} =
               Blog.create_article(scope, %{
                 title: "題",
                 slug: "s",
                 thumbnail_image_id: other_image.id
               })

      assert "選べない画像です" in errors_on(changeset).thumbnail_image_id
    end

    test "更新でも他クライアントのカテゴリに差し替えられない", %{scope: scope} do
      article = article_fixture(scope)
      other_category = category_fixture(Scope.for_user(user_fixture()))

      assert {:error, changeset} =
               Blog.update_article(scope, article, %{category_id: other_category.id})

      assert "選べないカテゴリです" in errors_on(changeset).category_id
    end

    test "自分のカテゴリと画像なら指定できる", %{scope: scope} do
      category = category_fixture(scope)
      image = image_fixture(scope)

      assert {:ok, article} =
               Blog.create_article(scope, %{
                 title: "題",
                 slug: "s",
                 category_id: category.id,
                 thumbnail_image_id: image.id
               })

      assert article.category.id == category.id
      assert article.thumbnail_image.id == image.id
    end
  end

  describe "list_articles/2" do
    setup %{scope: scope} do
      %{
        draft: article_fixture(scope, %{title: "下書きの記事"}),
        published: published_article_fixture(scope, %{title: "公開した記事"}),
        scheduled: scheduled_article_fixture(scope, %{title: "予約した記事"})
      }
    end

    test "既定では下書きも含めて全部返す", %{scope: scope} do
      assert length(Blog.list_articles(scope)) == 3
    end

    test "下書きで絞る", %{scope: scope, draft: draft} do
      assert Enum.map(Blog.list_articles(scope, filter: :draft), & &1.id) == [draft.id]
    end

    test "公開で絞ると予約投稿は含まれない", %{scope: scope, published: published} do
      assert Enum.map(Blog.list_articles(scope, filter: :published), & &1.id) == [published.id]
    end

    test "予約で絞る", %{scope: scope, scheduled: scheduled} do
      assert Enum.map(Blog.list_articles(scope, filter: :scheduled), & &1.id) == [scheduled.id]
    end

    test "タイトルで検索する", %{scope: scope, published: published} do
      assert Enum.map(Blog.list_articles(scope, q: "公開した"), & &1.id) == [published.id]
      assert Blog.list_articles(scope, q: "存在しない") == []
    end

    test "検索とフィルタを併用できる", %{scope: scope} do
      assert Blog.list_articles(scope, filter: :draft, q: "公開した") == []
      assert length(Blog.list_articles(scope, filter: :draft, q: "下書き")) == 1
    end

    test "⚠️ LIKE のワイルドカードをエスケープする", %{scope: scope} do
      article_fixture(scope, %{title: "割引100%セール"})

      assert Enum.map(Blog.list_articles(scope, q: "100%"), & &1.title) == ["割引100%セール"]
      assert Blog.list_articles(scope, q: "_") == []
    end

    test "⚠️ 他クライアントの記事は見えない", %{scope: scope} do
      other = article_fixture(Scope.for_user(user_fixture()), %{title: "他社の記事"})

      refute other.id in Enum.map(Blog.list_articles(scope), & &1.id)
    end

    test "更新が新しいものが先", %{scope: scope, draft: draft} do
      {:ok, _} = Blog.update_article(scope, draft, %{title: "更新した"})

      assert List.first(Blog.list_articles(scope)).id == draft.id
    end
  end

  describe "count_articles_by_filter/1" do
    test "絞り込みごとの件数を返す", %{scope: scope} do
      article_fixture(scope)
      published_article_fixture(scope)
      scheduled_article_fixture(scope)

      assert Blog.count_articles_by_filter(scope) == %{
               all: 3,
               draft: 1,
               published: 1,
               scheduled: 1
             }
    end

    test "⚠️ 他クライアントの記事を数えない", %{scope: scope} do
      article_fixture(Scope.for_user(user_fixture()))

      assert Blog.count_articles_by_filter(scope).all == 0
    end
  end

  describe "get_article!/2" do
    test "自分の記事は取得でき、関連が preload される", %{scope: scope} do
      category = category_fixture(scope)
      image = image_fixture(scope)
      article = article_fixture(scope, %{category_id: category.id, thumbnail_image_id: image.id})

      found = Blog.get_article!(scope, article.id)
      assert found.category.name == category.name
      assert found.thumbnail_image.filename == image.filename
    end

    test "⚠️ 他クライアントの記事は取得できない", %{scope: scope} do
      other = article_fixture(Scope.for_user(user_fixture()))

      assert_raise Ecto.NoResultsError, fn -> Blog.get_article!(scope, other.id) end
    end
  end

  describe "update_article/3" do
    test "本文を更新すると body_html も更新される", %{scope: scope} do
      article = article_fixture(scope, %{body: "初版"})

      assert {:ok, updated} = Blog.update_article(scope, article, %{body: "## 改訂"})
      assert updated.body_html =~ "<h2>改訂</h2>"
      refute updated.body_html =~ "初版"
    end

    test "本文を変えなければ body_html は再生成しない", %{scope: scope} do
      article = article_fixture(scope, %{body: "本文"})

      {:ok, updated} = Blog.update_article(scope, article, %{title: "題を変更"})
      assert updated.body_html == article.body_html
    end

    test "⚠️ 他クライアントの記事は更新できない", %{scope: scope} do
      other = article_fixture(Scope.for_user(user_fixture()))

      assert_raise MatchError, fn -> Blog.update_article(scope, other, %{title: "x"}) end
    end
  end

  describe "delete_article/2" do
    test "削除できる", %{scope: scope} do
      article = article_fixture(scope)

      assert {:ok, _} = Blog.delete_article(scope, article)
      assert Blog.list_articles(scope) == []
    end

    test "⚠️ 他クライアントの記事は削除できない", %{scope: scope} do
      other = article_fixture(Scope.for_user(user_fixture()))

      assert_raise MatchError, fn -> Blog.delete_article(scope, other) end
      assert Repo.get!(Article, other.id)
    end
  end

  describe "関連の削除に追随する" do
    test "画像を削除するとサムネイルが外れる（記事は残る）", %{scope: scope} do
      image = image_fixture(scope)
      article = article_fixture(scope, %{thumbnail_image_id: image.id})

      assert {:ok, _} = Media.delete_image(scope, image)
      assert Blog.get_article!(scope, article.id).thumbnail_image_id == nil
    end

    test "カテゴリを削除すると未分類になる（記事は残る）", %{scope: scope} do
      category = category_fixture(scope)
      article = article_fixture(scope, %{category_id: category.id})

      assert {:ok, _} = Blog.delete_category(scope, category)
      assert Blog.get_article!(scope, article.id).category_id == nil
    end
  end

  describe "PubSub" do
    test "作成・更新・削除が通知される", %{scope: scope} do
      Blog.subscribe_articles(scope)

      article = article_fixture(scope)
      assert_receive {:created, %Article{id: id}} when id == article.id

      {:ok, article} = Blog.update_article(scope, article, %{title: "更新"})
      assert_receive {:updated, %Article{id: id}} when id == article.id

      {:ok, _} = Blog.delete_article(scope, article)
      assert_receive {:deleted, %Article{id: id}} when id == article.id
    end
  end
end
