defmodule AntPressWeb.FlashTest do
  @moduledoc """
  トースト（フラッシュ）の表示。
  """
  use AntPressWeb.ConnCase

  import Phoenix.LiveViewTest
  import AntPress.BlogFixtures

  setup :register_and_log_in_user

  defp flash_tag(html, id) do
    case Regex.run(~r/<div[^>]*id="#{id}"[^>]*>/, html) do
      [tag] -> tag
      nil -> nil
    end
  end

  defp trigger_flash(conn, scope) do
    article = article_fixture(scope)
    {:ok, lv, _html} = live(conn, ~p"/client/articles")
    render_click(lv, "delete", %{"id" => article.id})
  end

  test "通常のトーストは自動で閉じる", %{conn: conn, scope: scope} do
    html = trigger_flash(conn, scope)

    assert html =~ "記事を削除しました"
    assert flash_tag(html, "flash-info") =~ "phx-hook"
  end

  test "⚠️ 接続断の通知は自動で閉じない", %{conn: conn, scope: scope} do
    # 状態が続いている間は出したままにする
    html = trigger_flash(conn, scope)

    refute flash_tag(html, "client-error") =~ "phx-hook"
    refute flash_tag(html, "server-error") =~ "phx-hook"
  end

  test "右下に出る", %{conn: conn, scope: scope} do
    html = trigger_flash(conn, scope)

    assert flash_tag(html, "flash-info") =~ "toast-bottom"
    assert flash_tag(html, "flash-info") =~ "toast-end"
  end

  test "接続エラーの通知も日本語", %{conn: conn, scope: scope} do
    html = trigger_flash(conn, scope)

    assert html =~ "ネットワークに接続できません"
    assert html =~ "接続が切れました"
    assert html =~ "再接続しています"
    refute html =~ "We can&#39;t find the internet"
    refute html =~ "Something went wrong"
  end

  test "colocated hook の script タグは描画に残らない", %{conn: conn, scope: scope} do
    # コンパイル時に app.js へ取り込まれる。1 ページに 4 回出たりしない
    html = trigger_flash(conn, scope)

    refute html =~ "<script"
  end
end
