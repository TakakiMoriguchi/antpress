defmodule AntPressWeb.DeveloperLive.Settings do
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

  alias AntPress.Platform

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_developer={@current_developer}>
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
        <p class="font-semibold">屋号</p>
        <p class="mt-1">{@current_developer.developer.name}</p>
      </div>

      <div class="rounded-lg border border-base-300 p-4">
        <p class="font-semibold">メールアドレス</p>
        <p class="mt-1">{@current_developer.developer.email}</p>
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
        <.button class="mt-3" navigate={~p"/developers/log-in"}>
          ログインし直す
        </.button>
      </div>

      <.form
        :if={@sudo_mode?}
        for={@password_form}
        id="password_form"
        action={~p"/developers/update-password"}
        method="post"
        phx-change="validate_password"
        phx-submit="update_password"
        phx-trigger-action={@trigger_submit}
      >
        <input
          name={@password_form[:email].name}
          type="hidden"
          id="hidden_developer_email"
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
    developer = socket.assigns.current_developer.developer
    password_changeset = Platform.change_developer_password(developer, %{}, hash_password: false)

    socket =
      socket
      |> assign(:current_email, developer.email)
      |> assign(:password_form, to_form(password_changeset))
      |> assign(:trigger_submit, false)
      |> assign(:sudo_mode?, Platform.sudo_mode?(socket.assigns.current_developer.developer))

    {:ok, socket}
  end

  @impl true
  def handle_event("validate_password", params, socket) do
    %{"developer" => developer_params} = params

    password_form =
      socket.assigns.current_developer.developer
      |> Platform.change_developer_password(developer_params, hash_password: false)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, password_form: password_form)}
  end

  def handle_event("update_password", params, socket) do
    %{"developer" => developer_params} = params
    developer = socket.assigns.current_developer.developer

    # ⚠️ 画面側でも出し分けているが、古い画面から送られる可能性がある。
    # `true = ...` で落とすと 500 になるので、案内を出して閉じる
    if Platform.sudo_mode?(developer) do
      do_update_password(socket, developer, developer_params)
    else
      {:noreply,
       socket
       |> assign(:sudo_mode?, false)
       |> put_flash(:error, "セキュリティのため、パスワードの変更にはログインし直しが必要です")}
    end
  end

  defp do_update_password(socket, developer, developer_params) do
    case Platform.change_developer_password(developer, developer_params) do
      %{valid?: true} = changeset ->
        {:noreply, assign(socket, trigger_submit: true, password_form: to_form(changeset))}

      changeset ->
        {:noreply, assign(socket, password_form: to_form(changeset, action: :insert))}
    end
  end
end
