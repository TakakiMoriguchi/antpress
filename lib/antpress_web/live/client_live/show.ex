defmodule AntPressWeb.ClientLive.Show do
  use AntPressWeb, :live_view

  alias AntPress.Platform

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_developer={@current_developer}>
      <.header>
        Client {@client.id}
        <:subtitle>This is a client record from your database.</:subtitle>
        <:actions>
          <.button navigate={~p"/clients"}>
            <.icon name="hero-arrow-left" />
          </.button>
          <.button variant="primary" navigate={~p"/clients/#{@client}/edit?return_to=show"}>
            <.icon name="hero-pencil-square" /> Edit client
          </.button>
        </:actions>
      </.header>

      <.list>
        <:item title="Name">{@client.name}</:item>
        <:item title="Slug">{@client.slug}</:item>
        <:item title="Plan">{@client.plan}</:item>
        <:item title="Contact notification email">{@client.contact_notification_email}</:item>
        <:item title="Webhook url">{@client.webhook_url}</:item>
        <:item title="Status">{@client.status}</:item>
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
     |> assign(:page_title, "Show Client")
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
end
