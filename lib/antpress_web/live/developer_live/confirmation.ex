defmodule AntPressWeb.DeveloperLive.Confirmation do
  use AntPressWeb, :live_view

  alias AntPress.Platform

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_developer={@current_developer}>
      <div class="mx-auto max-w-sm">
        <div class="text-center">
          <.header>ようこそ {@developer.email}</.header>
        </div>

        <.form
          :if={!@developer.confirmed_at}
          for={@form}
          id="confirmation_form"
          phx-mounted={JS.focus_first()}
          phx-submit="submit"
          action={~p"/developers/log-in?_action=confirmed"}
          phx-trigger-action={@trigger_submit}
        >
          <input type="hidden" name={@form[:token].name} value={@form[:token].value} />
          <.button
            name={@form[:remember_me].name}
            value="true"
            phx-disable-with="確認中..."
            class="btn btn-primary w-full"
          >
            確認してログインしたままにする
          </.button>
          <.button phx-disable-with="確認中..." class="btn btn-primary btn-soft w-full mt-2">
            確認して今回だけログイン
          </.button>
        </.form>

        <.form
          :if={@developer.confirmed_at}
          for={@form}
          id="login_form"
          phx-submit="submit"
          phx-mounted={JS.focus_first()}
          action={~p"/developers/log-in"}
          phx-trigger-action={@trigger_submit}
        >
          <input type="hidden" name={@form[:token].name} value={@form[:token].value} />
          <%= if @current_developer do %>
            <.button phx-disable-with="ログイン中..." class="btn btn-primary w-full">
              ログイン
            </.button>
          <% else %>
            <.button
              name={@form[:remember_me].name}
              value="true"
              phx-disable-with="ログイン中..."
              class="btn btn-primary w-full"
            >
              この端末でログインを保持する
            </.button>
            <.button
              phx-disable-with="ログイン中..."
              class="btn btn-primary btn-soft w-full mt-2"
            >
              今回だけログイン
            </.button>
          <% end %>
        </.form>

        <p :if={!@developer.confirmed_at} class="alert alert-outline mt-8">
          Tip: If you prefer passwords, you can enable them in the developer settings.
        </p>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    if developer = Platform.get_developer_by_magic_link_token(token) do
      form = to_form(%{"token" => token}, as: "developer")

      {:ok, assign(socket, developer: developer, form: form, trigger_submit: false),
       temporary_assigns: [form: nil]}
    else
      {:ok,
       socket
       |> put_flash(:error, "Magic link is invalid or it has expired.")
       |> push_navigate(to: ~p"/developers/log-in")}
    end
  end

  @impl true
  def handle_event("submit", %{"developer" => params}, socket) do
    {:noreply, assign(socket, form: to_form(params, as: "developer"), trigger_submit: true)}
  end
end
