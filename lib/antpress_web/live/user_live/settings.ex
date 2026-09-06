defmodule AntPressWeb.UserLive.Settings do
  @moduledoc """
  アカウント設定。

  **表示だけの画面**（表示テーマ・表示名・メールアドレス）。
  パスワードの変更は別ページに分けてある（→ `AntPressWeb.UserLive.Password`）。

  ## ⚠️ ここを sudo モードで塞がない

  生成時は `on_mount {..., :require_sudo_mode}` が付いていて、
  **最後の認証から 10 分を過ぎるとログイン画面へ飛ばされていた。**
  記事・カテゴリ・画像には自由に行けるのにここだけ弾かれるので、
  理由が分からず不具合に見える（実際に報告があった）。

  保護が要るのはパスワードの変更だけなので、そちらをページごと分けた。
  """
  use AntPressWeb, :live_view

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div class="text-center">
        <.header>
          アカウント設定
          <:subtitle>表示テーマの設定と、登録内容の確認ができます</:subtitle>
        </.header>
      </div>

      <div class="flex items-center justify-between gap-4 rounded-lg border border-base-300 p-4">
        <div>
          <p class="font-semibold">表示テーマ</p>
          <p class="text-sm opacity-60">システム設定に従う / ライト / ダーク</p>
        </div>
        <AntPressWeb.Layouts.theme_toggle />
      </div>

      <div class="rounded-lg border border-base-300 p-4">
        <p class="font-semibold">表示名</p>
        <p class="mt-1">{@current_user.user.name}</p>
      </div>

      <div class="rounded-lg border border-base-300 p-4">
        <p class="font-semibold">メールアドレス</p>
        <p class="mt-1">{@current_user.user.email}</p>
      </div>

      <div class="divider" />

      <div class="flex flex-wrap items-center justify-between gap-4 rounded-lg border border-base-300 p-4">
        <div>
          <p class="font-semibold">パスワード</p>
          <p class="text-sm opacity-60">変更にはログインし直しが必要になる場合があります</p>
        </div>
        <.button navigate={~p"/client/settings/password"}>パスワードを変更</.button>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "アカウント設定")}
  end
end
