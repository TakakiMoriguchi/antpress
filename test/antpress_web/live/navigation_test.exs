defmodule AntPressWeb.NavigationTest do
  @moduledoc """
  ナビゲーションの出し分け。

  ⚠️ **developer と client の両方でログインしている状態**を重点的に見る。
  ナビを `root.html.heex` に置いていたときは、`current_user` と
  `current_developer` を入れる plug がどちらも全リクエストで走るため、
  クライアント側の画面でも developer のナビが出て、記事・カテゴリ・画像へ
  移動できなくなっていた。
  """
  use AntPressWeb.ConnCase

  import Phoenix.LiveViewTest
  import AntPress.AccountsFixtures
  import AntPress.PlatformFixtures

  describe "client 側の画面" do
    setup :register_and_log_in_user

    test "クライアント用のナビが出る", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/client/articles")

      assert html =~ ">記事<"
      assert html =~ ">カテゴリ<"
      assert html =~ ">画像<"
      assert html =~ ~s(href="/client/log-out")
      refute html =~ ~s(href="/developers/log-out")
    end

    test "⚠️ developer でも同時にログインしていてもクライアント用のまま",
         %{conn: conn} do
      conn = log_in_developer(conn, developer_fixture())

      for path <- [~p"/client/articles", ~p"/client/categories", ~p"/client/images"] do
        {:ok, _lv, html} = live(conn, path)

        assert html =~ ">記事<", "#{path} でクライアント用のナビが出ていない"
        refute html =~ ">クライアント<", "#{path} で developer のナビが出ている"
        assert html =~ ~s(href="/client/log-out")
      end
    end
  end

  describe "developer 側の画面" do
    setup :register_and_log_in_developer

    test "developer 用のナビが出る", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/clients")

      assert html =~ ">クライアント<"
      assert html =~ ~s(href="/developers/log-out")
      refute html =~ ~s(href="/client/log-out")
    end

    test "⚠️ client でも同時にログインしていても developer 用のまま", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, _lv, html} = live(conn, ~p"/clients")

      assert html =~ ">クライアント<"
      refute html =~ ">記事<"
      assert html =~ ~s(href="/developers/log-out")
    end
  end

  describe "ルート（/）" do
    test "未ログインなら初期ページを出す", %{conn: conn} do
      assert html_response(get(conn, ~p"/"), 200)
    end

    test "developer はクライアント一覧へ送る", %{conn: conn} do
      conn = conn |> log_in_developer(developer_fixture()) |> get(~p"/")

      assert redirected_to(conn) == ~p"/clients"
    end

    test "client は記事一覧へ送る", %{conn: conn} do
      conn = conn |> log_in_user(user_fixture()) |> get(~p"/")

      assert redirected_to(conn) == ~p"/client/articles"
    end
  end
end
