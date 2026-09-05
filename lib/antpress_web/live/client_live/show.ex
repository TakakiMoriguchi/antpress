defmodule AntPressWeb.ClientLive.Show do
  use AntPressWeb, :live_view

  alias AntPress.Platform

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_developer={@current_developer}>
      <.header>
        {@client.name}
        <:subtitle>クライアントの設定</:subtitle>
        <:actions>
          <.button navigate={~p"/clients"}>
            <.icon name="hero-arrow-left" />
          </.button>
          <.button variant="primary" navigate={~p"/clients/#{@client}/edit?return_to=show"}>
            <.icon name="hero-pencil-square" /> 編集
          </.button>
        </:actions>
      </.header>

      <.list>
        <:item title="クライアント名">{@client.name}</:item>
        <:item title="識別名">{@client.slug}</:item>
        <:item title="プラン">{plan_label(@client.plan)}</:item>
        <:item title="問い合わせ通知先">{@client.contact_notification_email || "未設定"}</:item>
        <:item title="Webhook URL">{@client.webhook_url || "未設定"}</:item>
        <:item title="状態">{status_label(@client.status)}</:item>
      </.list>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    if connected?(socket) do
      Platform.subscribe_clients(socket.assigns.current_developer)
    end

    {:ok,
     socket
     |> assign(:page_title, "クライアント")
     |> assign(:client, Platform.get_client!(socket.assigns.current_developer, id))}
  end

  @impl true
  def handle_info(
        {:updated, %AntPress.Platform.Client{id: id} = client},
        %{assigns: %{client: %{id: id}}} = socket
      ) do
    {:noreply, assign(socket, :client, client)}
  end

  def handle_info(
        {:deleted, %AntPress.Platform.Client{id: id}},
        %{assigns: %{client: %{id: id}}} = socket
      ) do
    {:noreply,
     socket
     |> put_flash(:error, "The current client was deleted.")
     |> push_navigate(to: ~p"/clients")}
  end

  def handle_info({type, %AntPress.Platform.Client{}}, socket)
      when type in [:created, :updated, :deleted] do
    {:noreply, socket}
  end

  defp plan_label(:basic), do: "基本"
  defp plan_label(:ai), do: "AI"
  defp plan_label(nil), do: "—"

  defp status_label(:active), do: "稼働中"
  defp status_label(:suspended), do: "停止中"
  defp status_label(nil), do: "—"
end
