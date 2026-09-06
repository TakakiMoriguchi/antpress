defmodule AntPressWeb.DeveloperLive.Password do
  @moduledoc """
  パスワードの変更（developer / admin 側）。

  ## なぜアカウント設定から分けたか

  アカウント設定には表示テーマ・表示名・メールアドレスの表示が同居している。
  これらは読むだけで危険がないのに、**パスワード変更のために画面全体を
  保護すると、設定を見るだけでも再認証を求められる。**

  ページを分ければ「保護が要る操作」と「そうでない表示」の境界が
  URL と一致する（→ `docs/DECISIONS.md`）。

  ## ⚠️ 再認証が必要なときもログイン画面へ飛ばさない

  生成コードの `on_mount {..., :require_sudo_mode}` はリダイレクトするが、
  **どこから来たのか分からなくなる。** この画面ではその場に案内を出す。

  保護そのものは緩めていない。変更は LiveView のイベントと
  コントローラの両方で `sudo_mode?/1` を確認している。
  """
  use AntPressWeb, :live_view

  alias AntPress.Platform

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_developer={@current_developer}>
      <.header>
        パスワードの変更
        <:subtitle>新しいパスワードを設定します。</:subtitle>
      </.header>

      <%!-- ⚠️ 変更できるのは最後にログインしてから一定時間だけ。
            開きっぱなしの端末から乗っ取られるのを防ぐため --%>
      <div :if={!@sudo_mode?} class="rounded-lg border border-base-300 p-4">
        <p>セキュリティのため、パスワードの変更にはログインし直しが必要です。</p>
        <p class="mt-1 text-sm text-base-content/60">
          最後にログインしてから時間が経つと、この操作だけ再確認をお願いしています。
        </p>
        <.button class="mt-3" navigate={~p"/developers/log-in"}>ログインし直す</.button>
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
        <footer class="mt-6 flex flex-wrap gap-2">
          <.button variant="primary" phx-disable-with="保存中...">パスワードを変更</.button>
          <.button navigate={~p"/developers/settings"}>キャンセル</.button>
        </footer>
      </.form>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    developer = socket.assigns.current_developer.developer
    password_changeset = Platform.change_developer_password(developer, %{}, hash_password: false)

    {:ok,
     socket
     |> assign(:page_title, "パスワードの変更")
     |> assign(:current_email, developer.email)
     |> assign(:password_form, to_form(password_changeset))
     |> assign(:trigger_submit, false)
     |> assign(:sudo_mode?, Platform.sudo_mode?(developer))}
  end

  @impl true
  def handle_event("validate_password", %{"developer" => developer_params}, socket) do
    password_form =
      socket.assigns.current_developer.developer
      |> Platform.change_developer_password(developer_params, hash_password: false)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, password_form: password_form)}
  end

  def handle_event("update_password", %{"developer" => developer_params}, socket) do
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
