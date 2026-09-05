defmodule AntPressWeb.ClientLiveTest do
  use AntPressWeb.ConnCase

  import Phoenix.LiveViewTest
  import AntPress.PlatformFixtures

  @create_attrs %{
    name: "ラーメン太郎",
    status: :active,
    plan: :basic,
    slug: "ramen-taro",
    contact_notification_email: "owner@example.com",
    webhook_url: "https://api.vercel.com/v1/deploy/abc"
  }
  # plan: :ai にしない。AI プランは developer の Anthropic キー登録が前提のため
  # （→ docs/DECISIONS.md 3.1）。キー未登録の developer では検証で弾かれる
  @update_attrs %{
    name: "ラーメン太郎 本店",
    status: :suspended,
    plan: :basic,
    slug: "ramen-taro-honten",
    contact_notification_email: "owner2@example.com",
    webhook_url: "https://api.vercel.com/v1/deploy/xyz"
  }
  @invalid_attrs %{
    name: nil,
    status: nil,
    plan: nil,
    slug: nil,
    contact_notification_email: nil,
    webhook_url: nil
  }

  setup :register_and_log_in_developer

  defp create_client(%{scope: scope}) do
    client = client_fixture(scope)

    %{client: client}
  end

  describe "Index" do
    setup [:create_client]

    test "lists all clients", %{conn: conn, client: client} do
      {:ok, _index_live, html} = live(conn, ~p"/clients")

      assert html =~ "クライアント"
      assert html =~ client.name
    end

    test "saves new client", %{conn: conn} do
      {:ok, index_live, _html} = live(conn, ~p"/clients")

      assert {:ok, form_live, _} =
               index_live
               |> element("a", "クライアントを追加")
               |> render_click()
               |> follow_redirect(conn, ~p"/clients/new")

      assert render(form_live) =~ "クライアントを追加"

      assert form_live
             |> form("#client-form", client: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert {:ok, index_live, _html} =
               form_live
               |> form("#client-form", client: @create_attrs)
               |> render_submit()
               |> follow_redirect(conn, ~p"/clients")

      html = render(index_live)
      assert html =~ "クライアントを作成しました"
      assert html =~ "ラーメン太郎"
    end

    test "updates client in listing", %{conn: conn, client: client} do
      {:ok, index_live, _html} = live(conn, ~p"/clients")

      assert {:ok, form_live, _html} =
               index_live
               |> element("#clients-#{client.id} a", "編集")
               |> render_click()
               |> follow_redirect(conn, ~p"/clients/#{client}/edit")

      assert render(form_live) =~ "クライアントを編集"

      assert form_live
             |> form("#client-form", client: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert {:ok, index_live, _html} =
               form_live
               |> form("#client-form", client: @update_attrs)
               |> render_submit()
               |> follow_redirect(conn, ~p"/clients")

      html = render(index_live)
      assert html =~ "クライアントを更新しました"
      assert html =~ "ラーメン太郎 本店"
    end

    test "⚠️ 削除リンクを出さない", %{conn: conn, client: client} do
      # 削除は提供しない（→ docs/DECISIONS.md 3.8）
      {:ok, _index_live, html} = live(conn, ~p"/clients")

      assert html =~ client.name
      refute html =~ ">削除<"
    end

    test "稼働中 / 停止中で絞り込める", %{conn: conn, scope: scope, client: client} do
      {:ok, suspended} =
        AntPress.Platform.create_client(scope, %{
          name: "停止した店",
          slug: "suspended-shop",
          plan: :basic
        })

      {:ok, _} = AntPress.Platform.update_client(scope, suspended, %{status: :suspended})

      {:ok, lv, _html} = live(conn, ~p"/clients")

      html = lv |> element(~s(a[href="/clients?filter=active"])) |> render_click()
      assert html =~ client.name
      refute html =~ "停止した店"

      html = lv |> element(~s(a[href="/clients?filter=suspended"])) |> render_click()
      assert html =~ "停止した店"
      refute html =~ client.name
    end

    test "該当がなければ案内を出す", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/clients?filter=suspended")

      assert html =~ "停止中のクライアントはありません"
    end

    test "⚠️ 不正なフィルタ値でも落ちない", %{conn: conn, client: client} do
      {:ok, _lv, html} = live(conn, ~p"/clients?filter=../../etc/passwd")

      assert html =~ client.name
    end
  end

  describe "Show" do
    setup [:create_client]

    test "displays client", %{conn: conn, client: client} do
      {:ok, _show_live, html} = live(conn, ~p"/clients/#{client}")

      assert html =~ "クライアント"
      assert html =~ client.name
    end

    test "updates client and returns to show", %{conn: conn, client: client} do
      {:ok, show_live, _html} = live(conn, ~p"/clients/#{client}")

      assert {:ok, form_live, _} =
               show_live
               |> element("a", "編集")
               |> render_click()
               |> follow_redirect(conn, ~p"/clients/#{client}/edit?return_to=show")

      assert render(form_live) =~ "クライアントを編集"

      assert form_live
             |> form("#client-form", client: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert {:ok, show_live, _html} =
               form_live
               |> form("#client-form", client: @update_attrs)
               |> render_submit()
               |> follow_redirect(conn, ~p"/clients/#{client}")

      html = render(show_live)
      assert html =~ "クライアントを更新しました"
      assert html =~ "ラーメン太郎 本店"
    end
  end
end
