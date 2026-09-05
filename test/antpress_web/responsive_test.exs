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

      assert html =~ "flex flex-col items-start gap-3 sm:flex-row"
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
