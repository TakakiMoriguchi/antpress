defmodule AntPressWeb.ResponsiveTest do
  @moduledoc """
  狭い画面で崩れやすい箇所の構造を固定する。

  見た目そのものは自動テストで確かめられないので、
  **崩れの原因になる構造**（囲みの有無・切り替えクラスの有無）を見る。
  """
  use AntPressWeb.ConnCase

  import Phoenix.LiveViewTest
  import AntPress.BlogFixtures
  import AntPress.MediaFixtures
  import AntPress.PlatformFixtures

  describe "ナビゲーション" do
    setup :register_and_log_in_user

    test "⚠️ 狭い画面ではまとめる（5 項目を横に並べると溢れる）", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/client/articles")

      # 広い画面用は sm 以上でだけ出す
      assert html =~ ~r/class="menu menu-horizontal hidden[^"]*sm:flex"/
      # 狭い画面用のまとめ
      assert html =~ "dropdown dropdown-end sm:hidden"
      assert html =~ ~s(aria-label="メニュー")
    end

    test "項目の定義は 1 箇所（両方に同じ項目が出る）", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/client/articles")

      # 広い画面用と狭い画面用で 2 回ずつ出る
      for label <- ~w(記事 カテゴリ 画像 アカウント ログアウト) do
        assert length(Regex.scan(~r/>#{label}</, html)) >= 2,
               "#{label} が両方のメニューに出ていない"
      end
    end
  end

  describe "表" do
    setup :register_and_log_in_user

    test "⚠️ 横スクロールできる囲みがある", %{conn: conn, scope: scope} do
      # 囲みが無いと表がページ全体を横に押し広げる
      category_fixture(scope)
      {:ok, _lv, html} = live(conn, ~p"/client/categories")

      assert html =~ "overflow-x-auto"
    end

    test "記事一覧の副次的な列は狭い画面で隠れる", %{conn: conn, scope: scope} do
      article_fixture(scope)
      {:ok, _lv, html} = live(conn, ~p"/client/articles")

      assert html =~ ~s(class="hidden sm:table-cell">カテゴリ<)
      assert html =~ ~s(class="hidden md:table-cell">公開日時<)
      # 主要な列は常に出す
      assert html =~ ">タイトル<"
      assert html =~ ">状態<"
    end
  end

  describe "見出し" do
    setup :register_and_log_in_user

    test "狭い画面ではタイトルとボタンを縦に積む", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/client/articles")

      assert html =~ "flex flex-col gap-3 sm:flex-row"
    end

    test "⚠️ 狭い画面では主要ボタンを全幅にする", %{conn: conn} do
      # 左に寄せて積むと幅がばらばらになって不格好（指摘があった）。
      # items-start を付けないことで flex の既定（stretch）が効く
      {:ok, _lv, html} = live(conn, ~p"/client/articles")

      refute html =~ "flex flex-col items-start gap-3"
      assert html =~ "flex flex-col gap-2 sm:flex-none sm:flex-row"
    end

    test "⚠️ 狭い画面では絞り込みタブを全幅・等分にする", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/client/articles")

      assert html =~ "tabs tabs-box w-full flex-wrap sm:w-auto"
      assert html =~ "tab flex-1 sm:flex-none"
    end
  end

  describe "記事フォーム" do
    setup :register_and_log_in_user

    test "検索欄とタイトル欄の高さを揃える", %{conn: conn} do
      # 一覧の検索欄が input-sm で、フォームの input より小さく見えていた
      {:ok, _lv, list} = live(conn, ~p"/client/articles")

      refute list =~ "input-sm"
      assert list =~ ~s(class="input w-full sm:w-64")
    end

    test "サムネイル欄とフッターが折り返せる", %{conn: conn, scope: scope} do
      image = image_fixture(scope)
      article = article_fixture(scope, %{thumbnail_image_id: image.id})

      {:ok, _lv, html} = live(conn, ~p"/client/articles/#{article}/edit")

      assert html =~ "mt-2 flex flex-wrap items-center gap-4"
      assert html =~ "mt-6 flex flex-wrap gap-2"
    end
  end

  describe "developer 側" do
    setup :register_and_log_in_developer

    test "ナビは狭い画面でまとめる", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/clients")

      assert html =~ "dropdown dropdown-end sm:hidden"
    end

    test "クライアント一覧の副次的な列は狭い画面で隠れる", %{conn: conn, scope: scope} do
      client_fixture(scope)
      {:ok, _lv, html} = live(conn, ~p"/clients")

      assert html =~ ~s(class="hidden sm:table-cell">識別名<)
      assert html =~ ~s(class="hidden lg:table-cell">問い合わせ通知先<)
      assert html =~ ">クライアント名<"
    end
  end

  describe "フォーム部品の大きさ" do
    setup :register_and_log_in_user

    test "⚠️ ラベルの見た目が全項目で揃っている", %{conn: conn} do
      # .fieldset の font-size: 0.75rem と .label の 60% 不透明度が
      # 重なって、.input のラベルだけ極端に小さく薄くなっていた
      {:ok, _lv, html} = live(conn, ~p"/client/articles/new")

      expected = "mb-1.5 block text-base font-medium text-base-content"

      for label <- ~w(タイトル 本文 サムネイル カテゴリ 公開状態) do
        assert html =~ ~r/<(?:span|label)[^>]*class="#{Regex.escape(expected)}"[^>]*>\s*#{label}/,
               "「#{label}」のラベルが他と揃っていない"
      end
    end

    test "daisyUI の .label をそのまま使わない", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/client/articles/new")

      refute html =~ ~s(class="label mb-1")
      refute html =~ ~s(class="label")
    end

    test "項目の間隔を確保している", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/client/articles/new")

      assert html =~ "fieldset mb-5"
      refute html =~ "fieldset mb-2"
    end

    test "入力欄を小さくしない", %{conn: conn, scope: scope} do
      # 全体のサイズは --size-field（assets/css/app.css）で決まる。
      # 個別に input-sm を付けると揃わなくなる
      image_fixture(scope)
      {:ok, _lv, images} = live(conn, ~p"/client/images")
      {:ok, _lv, articles} = live(conn, ~p"/client/articles")

      refute images =~ "input-sm"
      refute articles =~ "input-sm"
    end
  end

  describe "トースト" do
    setup :register_and_log_in_user

    test "画面幅を超えない", %{conn: conn, scope: scope} do
      article = article_fixture(scope)
      {:ok, lv, _html} = live(conn, ~p"/client/articles")
      html = render_click(lv, "delete", %{"id" => article.id})

      assert html =~ "w-[calc(100vw_-_2rem)] sm:w-96"
    end
  end
end
