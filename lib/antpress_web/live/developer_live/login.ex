defmodule AntPressWeb.DeveloperLive.Login do
  use AntPressWeb, :live_view

  alias AntPress.Platform

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_developer={@current_developer}>
      <div class="mx-auto max-w-sm space-y-4">
        <div class="text-center">
          <.header>
            <p>antpress にログイン</p>
            <:subtitle>
              <%= if @current_developer do %>
                重要な操作を行うため、再認証が必要です。
              <% else %>
                アカウントは運営者が発行します。お持ちでない場合はお問い合わせください。
              <% end %>
            </:subtitle>
          </.header>
        </div>

        <div :if={local_mail_adapter?()} class="alert alert-info">
          <.icon name="hero-information-circle" class="size-6 shrink-0" />
          <div>
            <p>開発用のメールアダプタで動作しています。</p>
            <p>
              送信されたメールは <.link href="/dev/mailbox" class="underline">メールボックス</.link> で確認できます。
            </p>
          </div>
        </div>

        <.form
          :let={f}
          for={@form}
          id="login_form_magic"
          action={~p"/developers/log-in"}
          phx-submit="submit_magic"
        >
          <.input
            readonly={!!@current_developer}
            field={f[:email]}
            type="email"
            label="メールアドレス"
            autocomplete="username"
            spellcheck="false"
            required
            phx-mounted={JS.focus()}
          />
          <.button class="btn btn-primary w-full">
            メールでログイン <span aria-hidden="true">→</span>
          </.button>
        </.form>

        <div class="divider">または</div>

        <.form
          :let={f}
          for={@form}
          id="login_form_password"
          action={~p"/developers/log-in"}
          phx-submit="submit_password"
          phx-trigger-action={@trigger_submit}
        >
          <.input
            readonly={!!@current_developer}
            field={f[:email]}
            type="email"
            label="メールアドレス"
            autocomplete="username"
            spellcheck="false"
            required
          />
          <.input
            field={@form[:password]}
            type="password"
            label="パスワード"
            autocomplete="current-password"
            spellcheck="false"
          />
          <.button class="btn btn-primary w-full" name={@form[:remember_me].name} value="true">
            ログインしたままにする <span aria-hidden="true">→</span>
          </.button>
          <.button class="btn btn-primary btn-soft w-full mt-2">
            今回だけログイン
          </.button>
        </.form>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    email =
      Phoenix.Flash.get(socket.assigns.flash, :email) ||
        get_in(socket.assigns, [:current_developer, Access.key(:developer), Access.key(:email)])

    form = to_form(%{"email" => email}, as: "developer")

    {:ok, assign(socket, form: form, trigger_submit: false)}
  end

  @impl true
  def handle_event("submit_password", _params, socket) do
    {:noreply, assign(socket, :trigger_submit, true)}
  end

  def handle_event("submit_magic", %{"developer" => %{"email" => email}}, socket) do
    if developer = Platform.get_developer_by_email(email) do
      Platform.deliver_login_instructions(
        developer,
        &url(~p"/developers/log-in/#{&1}")
      )
    end

    info =
      "If your email is in our system, you will receive instructions for logging in shortly."

    {:noreply,
     socket
     |> put_flash(:info, info)
     |> push_navigate(to: ~p"/developers/log-in")}
  end

  defp local_mail_adapter? do
    Application.get_env(:antpress, AntPress.Mailer)[:adapter] == Swoosh.Adapters.Local
  end
end
