defmodule AntPressWeb.PageController do
  use AntPressWeb, :controller

  @doc """
  ルート（`/`）。

  ⚠️ **ログイン済みならそれぞれの管理画面へ送る。**

  このページは Phoenix の初期テンプレートのままで、`Layouts.app` を
  使っていない（＝ナビが出ない）。ログイン中のユーザーがここに来ると
  antpress と無関係な画面に取り残されるため、行き先へ飛ばす。

  developer と client の両方でログインしている場合は developer を優先する。
  """
  def home(conn, _params) do
    cond do
      conn.assigns[:current_developer] ->
        redirect(conn, to: ~p"/clients")

      conn.assigns[:current_user] && conn.assigns.current_user.user ->
        redirect(conn, to: ~p"/client/articles")

      true ->
        render(conn, :home)
    end
  end
end
