defmodule AntPressWeb.ClientLive.Index do
  use AntPressWeb, :live_view

  alias AntPress.Platform

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_developer={@current_developer}>
      <.header>
        クライアント
        <:actions>
          <.button variant="primary" navigate={~p"/clients/new"}>
            <.icon name="hero-plus" /> クライアントを追加
          </.button>
        </:actions>
      </.header>

      <.table
        id="clients"
        rows={@streams.clients}
        row_click={fn {_id, client} -> JS.navigate(~p"/clients/#{client}") end}
      >
        <:col :let={{_id, client}} label="クライアント名">{client.name}</:col>
        <:col :let={{_id, client}} label="スラッグ">{client.slug}</:col>
        <:col :let={{_id, client}} label="プラン">{plan_label(client.plan)}</:col>
        <:col :let={{_id, client}} label="問い合わせ通知先">
          {client.contact_notification_email}
        </:col>
        <:col :let={{_id, client}} label="Webhook URL">{webhook_label(client.webhook_url)}</:col>
        <:col :let={{_id, client}} label="状態">{status_label(client.status)}</:col>
        <:action :let={{_id, client}}>
          <div class="sr-only">
            <.link navigate={~p"/clients/#{client}"}>詳細</.link>
          </div>
          <.link navigate={~p"/clients/#{client}/edit"}>編集</.link>
        </:action>
        <:action :let={{id, client}}>
          <.link
            phx-click={JS.push("delete", value: %{id: client.id}) |> hide("##{id}")}
            data-confirm="このクライアントを削除します。記事・画像・問い合わせもすべて失われます。よろしいですか？"
          >
            削除
          </.link>
        </:action>
      </.table>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Platform.subscribe_clients(socket.assigns.current_developer)
    end

    {:ok,
     socket
     |> assign(:page_title, "クライアント")
     |> stream(:clients, list_clients(socket.assigns.current_developer))}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    client = Platform.get_client!(socket.assigns.current_developer, id)
    {:ok, _} = Platform.delete_client(socket.assigns.current_developer, client)

    {:noreply, stream_delete(socket, :clients, client)}
  end

  @impl true
  def handle_info({type, %AntPress.Platform.Client{}}, socket)
      when type in [:created, :updated, :deleted] do
    {:noreply,
     stream(socket, :clients, list_clients(socket.assigns.current_developer), reset: true)}
  end

  defp list_clients(current_developer) do
    Platform.list_clients(current_developer)
  end

  # ─── 表示用ヘルパー ─────────────────────────────
  defp plan_label(:basic), do: "基本"
  defp plan_label(:ai), do: "AI"
  defp plan_label(nil), do: "—"

  defp status_label(:active), do: "稼働中"
  defp status_label(:suspended), do: "停止中"
  defp status_label(nil), do: "—"

  # URL 全体を出すと表が崩れるので設定済みかどうかだけ示す
  defp webhook_label(nil), do: "未設定"
  defp webhook_label(""), do: "未設定"
  defp webhook_label(_url), do: "設定済み"
end
