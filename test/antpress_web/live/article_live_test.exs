defmodule AntPressWeb.ArticleLiveTest do
  use AntPressWeb.ConnCase

  import Phoenix.LiveViewTest
  import AntPress.AccountsFixtures
  import AntPress.BlogFixtures
  import AntPress.MediaFixtures

  alias AntPress.Accounts.Scope
  alias AntPress.Blog

  setup :register_and_log_in_user

  describe "認可" do
    test "ログインしていないとログイン画面へ飛ばされる" do
      assert {:error, {:redirect, %{to: "/client/log-in"}}} =
               live(build_conn(), ~p"/client/articles")

      assert {:error, {:redirect, %{to: "/client/log-in"}}} =
               live(build_conn(), ~p"/client/articles/new")
    end
  end

  describe "一覧（C3）" do
    test "記事がなければ案内を出す", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/client/articles")

      assert html =~ "まだ記事がありません"
      assert html =~ "記事を書く"
    end

    test "記事とその状態を表示する", %{conn: conn, scope: scope} do
      draft = article_fixture(scope, %{title: "下書きの記事"})
      published_article_fixture(scope, %{title: "公開した記事"})
      scheduled_article_fixture(scope, %{title: "予約した記事"})

      {:ok, _lv, html} = live(conn, ~p"/client/articles")

      assert html =~ "下書きの記事"
      assert html =~ "公開した記事"
      assert html =~ "予約した記事"
      assert html =~ "/#{draft.slug}"
      # 予約は専用ステータスではないが表示は分ける
      assert html =~ "下書き"
      assert html =~ "予約"
    end

    test "カテゴリ未設定は「未分類」と出る", %{conn: conn, scope: scope} do
      article_fixture(scope)

      {:ok, _lv, html} = live(conn, ~p"/client/articles")
      assert html =~ "未分類"
    end

    test "サムネイルを表示する", %{conn: conn, scope: scope} do
      image = image_fixture(scope)
      article_fixture(scope, %{thumbnail_image_id: image.id})

      {:ok, _lv, html} = live(conn, ~p"/client/articles")
      assert html =~ AntPress.Media.public_url(image)
    end

    test "絞り込みタブが機能する", %{conn: conn, scope: scope} do
      article_fixture(scope, %{title: "下書きの記事"})
      published_article_fixture(scope, %{title: "公開した記事"})

      {:ok, lv, _html} = live(conn, ~p"/client/articles")

      html = lv |> element(~s(a[href="/client/articles?filter=draft"])) |> render_click()
      assert html =~ "下書きの記事"
      refute html =~ "公開した記事"

      html = lv |> element(~s(a[href="/client/articles?filter=published"])) |> render_click()
      assert html =~ "公開した記事"
      refute html =~ "下書きの記事"
    end

    test "URL のフィルタを直接指定できる", %{conn: conn, scope: scope} do
      article_fixture(scope, %{title: "下書きの記事"})
      scheduled_article_fixture(scope, %{title: "予約した記事"})

      {:ok, _lv, html} = live(conn, ~p"/client/articles?filter=scheduled")
      assert html =~ "予約した記事"
      refute html =~ "下書きの記事"
    end

    test "⚠️ 不正なフィルタ値でも落ちない", %{conn: conn, scope: scope} do
      article_fixture(scope, %{title: "下書きの記事"})

      {:ok, _lv, html} = live(conn, ~p"/client/articles?filter=../../etc/passwd")
      assert html =~ "下書きの記事"
    end

    test "タイトルで検索できる", %{conn: conn, scope: scope} do
      article_fixture(scope, %{title: "ラーメンの話"})
      article_fixture(scope, %{title: "餃子の話"})

      {:ok, lv, _html} = live(conn, ~p"/client/articles")

      html = lv |> form("form[phx-change='search']", %{q: "ラーメン"}) |> render_change()
      assert html =~ "ラーメンの話"
      refute html =~ "餃子の話"
    end

    test "検索でヒットしないときの案内", %{conn: conn, scope: scope} do
      article_fixture(scope, %{title: "ラーメンの話"})

      {:ok, lv, _html} = live(conn, ~p"/client/articles")
      html = lv |> form("form[phx-change='search']", %{q: "寿司"}) |> render_change()

      assert html =~ "「寿司」に一致する記事はありません"
    end

    test "削除できる", %{conn: conn, scope: scope} do
      article = article_fixture(scope, %{title: "消す記事"})

      {:ok, lv, html} = live(conn, ~p"/client/articles")
      assert html =~ "消す記事"

      html = render_click(lv, "delete", %{"id" => article.id})
      refute html =~ "消す記事"
      assert html =~ "記事を削除しました"
    end

    test "⚠️ 他クライアントの記事は表示・削除できない", %{conn: conn, scope: scope} do
      Process.flag(:trap_exit, true)
      article_fixture(scope, %{title: "自社の記事"})
      other = article_fixture(Scope.for_user(user_fixture()), %{title: "他社の記事"})

      {:ok, lv, html} = live(conn, ~p"/client/articles")
      assert html =~ "自社の記事"
      refute html =~ "他社の記事"

      assert catch_exit(render_click(lv, "delete", %{"id" => other.id}))
      assert AntPress.Repo.get!(AntPress.Blog.Article, other.id)
    end
  end

  describe "編集画面（C4）" do
    test "新規作成画面が開く", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/client/articles/new")

      assert html =~ "記事を書く"
      assert html =~ "タイトル"
      assert html =~ "サムネイル"
      # ⚠️「スラッグ」は WordPress 用語で店舗オーナーに通じない
      refute html =~ "スラッグ"
      # 新規作成時はアドレスがまだ無いので表示しない
      refute html =~ "記事のアドレス"
    end

    test "⚠️ エディタに phx-update=\"ignore\" が付いている", %{conn: conn} do
      # 付けないと LiveView の DOM パッチで Toast UI が壊れる
      {:ok, _lv, html} = live(conn, ~p"/client/articles/new")

      assert html =~ ~s(phx-update="ignore")
      assert html =~ "article-editor-new"
    end

    test "⚠️ 本文の hidden input が ignore の中にある", %{conn: conn} do
      # 外に置くと、他フィールドの検証で再描画されたときに
      # JS が入れた本文がサーバー側の古い値へ巻き戻る
      {:ok, _lv, html} = live(conn, ~p"/client/articles/new")

      [editor_block] = Regex.run(~r/<div id="article-editor-new".*?<\/div>\s*<\/div>/s, html)

      assert editor_block =~ ~s(phx-update="ignore")
      assert editor_block =~ ~s(name="article[body]")
      assert editor_block =~ ~s(name="article[body_format]")
    end

    test "Toast UI Editor の読み込み先を data 属性で渡す", %{conn: conn} do
      # 522KB を app.js に入れて全ページに負わせない
      {:ok, _lv, html} = live(conn, ~p"/client/articles/new")

      assert html =~ "/vendor/toastui-editor/toastui-editor-all.min.js"
      assert html =~ "/vendor/toastui-editor/toastui-editor.min.css"
      assert html =~ "/vendor/toastui-editor/i18n-ja-jp.min.js"
    end

    test "⚠️ script タグをテンプレートに置かない", %{conn: conn} do
      # LiveView のテンプレートに置いた script は live navigation で
      # 実行されない（morphdom で挿入されたスクリプトはブラウザが動かさない）。
      # 一覧から「記事を書く」を押したときだけ壊れる、という形で実際に出た
      {:ok, _lv, html} = live(conn, ~p"/client/articles/new")

      refute html =~ "<script src="
      refute html =~ "<script phx-track-static"
      # フックが data 属性を読んで動的に読み込む
      assert html =~ "data-editor-js="
    end

    test "記事を作成すると編集画面へ遷移する", %{conn: conn, scope: scope} do
      {:ok, lv, _html} = live(conn, ~p"/client/articles/new")

      params = %{
        "title" => "新メニューのお知らせ",
        "body" => "# 見出し\n\n本文です。",
        "body_format" => "markdown",
        "status" => "draft"
      }

      # ⚠️ body は hidden input で、実際はエディタの JS が値を入れる。
      # LiveViewTest の form/3 は hidden input を書き換えられないので
      # ブラウザが送るのと同じ params を直接送る
      assert {:error, {:live_redirect, %{to: to}}} =
               render_submit(lv, "save", %{"article" => params})

      assert [article] = Blog.list_articles(scope)
      assert to == "/client/articles/#{article.id}/edit"
      assert article.title == "新メニューのお知らせ"
      assert article.body_html =~ "<h1>見出し</h1>"
    end

    test "検証エラーを表示する", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/client/articles/new")

      html =
        lv
        |> form("#article-form", article: %{"title" => ""})
        |> render_submit()

      assert html =~ "can&#39;t be blank" or html =~ "can't be blank"
    end

    test "⚠️ アドレスの入力欄を出さず、編集画面では読み取り専用で見せる", %{conn: conn, scope: scope} do
      # 公開後に URL が変わると既存のリンクが 404 になるため編集させない
      article = article_fixture(scope)

      {:ok, _lv, html} = live(conn, ~p"/client/articles/#{article}/edit")

      assert html =~ "記事のアドレス"
      assert html =~ article.slug
      assert html =~ "自動で決まり、変更できません"
      refute html =~ ~s(name="article[slug]")
    end

    test "既存記事を編集画面に読み込む", %{conn: conn, scope: scope} do
      article = article_fixture(scope, %{title: "元のタイトル", body: "元の本文"})

      {:ok, _lv, html} = live(conn, ~p"/client/articles/#{article}/edit")

      assert html =~ "記事を編集"
      assert html =~ "元のタイトル"

      # エディタの初期値は data 属性で渡す（ignore なので描画で上書きしない）
      assert html =~ "元の本文"
      assert html =~ "article-editor-#{article.id}"
    end

    test "保存できる", %{conn: conn, scope: scope} do
      article = article_fixture(scope, %{title: "元のタイトル"})

      {:ok, lv, _html} = live(conn, ~p"/client/articles/#{article}/edit")

      html =
        render_submit(lv, "save", %{
          "article" => %{"title" => "新しいタイトル", "body" => "## 改訂"}
        })

      assert html =~ "記事を保存しました"
      updated = Blog.get_article!(scope, article.id)
      assert updated.title == "新しいタイトル"
      assert updated.body_html =~ "<h2>改訂</h2>"
    end

    test "カテゴリを選べる", %{conn: conn, scope: scope} do
      category = category_fixture(scope, %{name: "季節限定"})
      {:ok, _lv, html} = live(conn, ~p"/client/articles/new")

      assert html =~ "季節限定"
      assert html =~ category.id
    end

    test "⚠️ 他クライアントのカテゴリは選択肢に出ない", %{conn: conn} do
      other = category_fixture(Scope.for_user(user_fixture()), %{name: "他社のカテゴリ"})

      {:ok, _lv, html} = live(conn, ~p"/client/articles/new")
      refute html =~ "他社のカテゴリ"
      refute html =~ other.id
    end

    test "⚠️ 他クライアントの記事は開けない", %{conn: conn} do
      other = article_fixture(Scope.for_user(user_fixture()))

      assert_raise Ecto.NoResultsError, fn ->
        live(conn, ~p"/client/articles/#{other}/edit")
      end
    end
  end

  describe "サムネイル選択" do
    test "画像がなくてもモーダル内でアップロードできる", %{conn: conn} do
      # ⚠️ ここから画像管理へ遷移させると書きかけの記事が失われる
      {:ok, lv, _html} = live(conn, ~p"/client/articles/new")

      html = lv |> element("button", "画像を選択") |> render_click()

      assert html =~ "まだ画像がありません"
      assert html =~ "クリックして選択、またはここにドラッグ＆ドロップ"
      # 画像管理へのリンクは残すが、別タブで開く
      assert html =~ ~s(target="_blank")
      refute html =~ ~s(data-phx-link="redirect" href="/client/images")
    end

    test "モーダルからアップロードするとサムネイルに設定される", %{conn: conn, scope: scope} do
      {:ok, lv, _html} = live(conn, ~p"/client/articles/new")
      lv |> element("button", "画像を選択") |> render_click()

      html =
        lv
        |> file_input("#thumbnail-upload", :thumbnail, [
          %{name: "gaikan.png", content: png(1200, 630)}
        ])
        |> render_upload("gaikan.png")

      assert [image] = AntPress.Media.list_images(scope)
      assert image.filename == "gaikan.png"
      assert html =~ "画像をアップロードしてサムネイルに設定しました"
      # モーダルは閉じ、サムネイルとして表示される
      refute html =~ "サムネイルを選択"
      assert html =~ AntPress.Media.public_url(image)
    end

    test "アップロードしたサムネイルをそのまま保存できる", %{conn: conn, scope: scope} do
      {:ok, lv, _html} = live(conn, ~p"/client/articles/new")
      lv |> element("button", "画像を選択") |> render_click()

      lv
      |> file_input("#thumbnail-upload", :thumbnail, [
        %{name: "gaikan.png", content: png()}
      ])
      |> render_upload("gaikan.png")

      [image] = AntPress.Media.list_images(scope)

      render_submit(lv, "save", %{
        "article" => %{"title" => "題", "thumbnail_image_id" => image.id}
      })

      assert [article] = AntPress.Blog.list_articles(scope)
      assert article.thumbnail_image_id == image.id
    end

    test "⚠️ 対応していない形式はモーダル内で弾く", %{conn: conn, scope: scope} do
      {:ok, lv, _html} = live(conn, ~p"/client/articles/new")
      lv |> element("button", "画像を選択") |> render_click()

      html =
        lv
        |> file_input("#thumbnail-upload", :thumbnail, [
          %{name: "evil.png", content: "<script>alert(1)</script>"}
        ])
        |> render_upload("evil.png")

      assert html =~ "対応していない画像形式です"
      assert AntPress.Media.list_images(scope) == []
    end

    test "画像を選ぶとサムネイルに設定される", %{conn: conn, scope: scope} do
      image = image_fixture(scope, %{filename: "gaikan.png"})

      {:ok, lv, _html} = live(conn, ~p"/client/articles/new")

      html = lv |> element("button", "画像を選択") |> render_click()
      assert html =~ "gaikan.png"

      html = render_click(lv, "select-thumbnail", %{"id" => image.id})
      assert html =~ image.id
      refute html =~ "サムネイルを選択"
    end

    test "選んだサムネイルを保存できる", %{conn: conn, scope: scope} do
      image = image_fixture(scope)

      {:ok, lv, _html} = live(conn, ~p"/client/articles/new")
      lv |> element("button", "画像を選択") |> render_click()
      render_click(lv, "select-thumbnail", %{"id" => image.id})

      render_submit(lv, "save", %{
        "article" => %{"title" => "題", "thumbnail_image_id" => image.id}
      })

      assert [article] = Blog.list_articles(scope)
      assert article.thumbnail_image_id == image.id
    end

    test "⚠️ 他クライアントの画像は選択肢に出ず、指定しても落ちる", %{conn: conn} do
      Process.flag(:trap_exit, true)
      other = image_fixture(Scope.for_user(user_fixture()), %{filename: "theirs.png"})

      {:ok, lv, _html} = live(conn, ~p"/client/articles/new")
      html = lv |> element("button", "画像を選択") |> render_click()
      refute html =~ "theirs.png"

      assert catch_exit(render_click(lv, "select-thumbnail", %{"id" => other.id}))
    end
  end

  describe "ナビゲーション" do
    test "メニューに「記事」が出る", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/client/articles")

      assert html =~ ~s(href="/client/articles")
    end
  end
end
