defmodule AntPressWeb.UserLive.Settings do
  @moduledoc """
  アカウント設定。

  ## ⚠️ ページ全体を sudo モードで塞がない

  生成時は `on_mount {..., :require_sudo_mode}` が付いていて、
  **最後の認証から 10 分を過ぎるとログイン画面へ飛ばされていた。**
  記事・カテゴリ・画像には自由に行けるのにここだけ弾かれるので、
  理由が分からず不具合に見える（実際に報告があった）。

  この画面の中身のうち、保護が要るのは**パスワードの変更だけ**。
  表示テーマ・表示名・メールアドレスの表示は読むだけで危険がない。

  そこで**パスワード変更の部分だけ**を出し分けるようにした。
  変更そのものは LiveView のイベントとコントローラの両方で
  `sudo_mode?/1` を確認しているので、画面を出すことによる緩みはない。
  """
  use AntPressWeb, :live_view

  alias AntPress.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div class="text-center">
        <.header>
          アカウント設定
          <:subtitle>パスワードの変更と表示テーマの設定ができます</:subtitle>
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

      <p class="font-semibold">パスワード</p>

      <%!-- ⚠️ 変更できるのは最後にログインしてから一定時間だけ。
            開きっぱなしの端末から乗っ取られるのを防ぐため。
            **ページごと弾かずにこの部分だけ出し分ける** --%>
      <div :if={!@sudo_mode?} class="rounded-lg border border-base-300 p-4">
        <p>セキュリティのため、パスワードの変更にはログインし直しが必要です。</p>
        <p class="mt-1 text-sm text-base-content/60">
          最後にログインしてから時間が経つと、この操作だけ再確認をお願いしています。
        </p>
        <.button class="mt-3" navigate={~p"/client/log-in"}>
          ログインし直す
        </.button>
      </div>

      <.form
        :if={@sudo_mode?}
        for={@password_form}
        id="password_form"
        action={~p"/client/update-password"}
        method="post"
        phx-change="validate_password"
        phx-submit="update_password"
        phx-trigger-action={@trigger_submit}
      >
        <input
          name={@password_form[:email].name}
          type="hidden"
          id="hidden_user_email"
          spellcheck="false"
          value={@current_email}
        />
        <.input
          field={@password_form[:password]}
          type="password"
          label="新しいパスワード"
          autocomplete="new-password"
          spellcheck="false"
          required
        />
        <.input
          field={@password_form[:password_confirmation]}
          type="password"
          label="新しいパスワード（確認）"
          autocomplete="new-password"
          spellcheck="false"
        />
        <.button variant="primary" phx-disable-with="保存中...">
          パスワードを変更
        </.button>
      </.form>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user.user
    password_changeset = Accounts.change_user_password(user, %{}, hash_password: false)

    socket =
      socket
      |> assign(:current_email, user.email)
      |> assign(:password_form, to_form(password_changeset))
      |> assign(:trigger_submit, false)
      |> assign(:sudo_mode?, Accounts.sudo_mode?(socket.assigns.current_user.user))

    {:ok, socket}
  end

  @impl true
  def handle_event("validate_password", params, socket) do
    %{"user" => user_params} = params

    password_form =
      socket.assigns.current_user.user
      |> Accounts.change_user_password(user_params, hash_password: false)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, password_form: password_form)}
  end

  def handle_event("update_password", params, socket) do
    %{"user" => user_params} = params
    user = socket.assigns.current_user.user

    # ⚠️ 画面側でも出し分けているが、古い画面から送られる可能性がある。
    # `true = ...` で落とすと 500 になるので、案内を出して閉じる
    if Accounts.sudo_mode?(user) do
      do_update_password(socket, user, user_params)
    else
      {:noreply,
       socket
       |> assign(:sudo_mode?, false)
       |> put_flash(:error, "セキュリティのため、パスワードの変更にはログインし直しが必要です")}
    end
  end

  defp do_update_password(socket, user, user_params) do
    case Accounts.change_user_password(user, user_params) do
      %{valid?: true} = changeset ->
        {:noreply, assign(socket, trigger_submit: true, password_form: to_form(changeset))}

      changeset ->
        {:noreply, assign(socket, password_form: to_form(changeset, action: :insert))}
    end
  end
end
