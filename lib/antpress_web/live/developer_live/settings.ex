defmodule AntPressWeb.DeveloperLive.Settings do
  use AntPressWeb, :live_view

  on_mount {AntPressWeb.DeveloperAuth, :require_sudo_mode}

  alias AntPress.Platform

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_developer={@current_developer}>
      <div class="text-center">
        <.header>
          アカウント設定
          <:subtitle>メールアドレスとパスワードを変更できます</:subtitle>
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

      <.form
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
          Save Password
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
    true = Platform.sudo_mode?(developer)

    case Platform.change_developer_password(developer, developer_params) do
      %{valid?: true} = changeset ->
        {:noreply, assign(socket, trigger_submit: true, password_form: to_form(changeset))}

      changeset ->
        {:noreply, assign(socket, password_form: to_form(changeset, action: :insert))}
    end
  end
end
