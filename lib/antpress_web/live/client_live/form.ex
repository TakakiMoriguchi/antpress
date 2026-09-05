defmodule AntPressWeb.ClientLive.Form do
  use AntPressWeb, :live_view

  alias AntPress.Platform
  alias AntPress.Platform.Client

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_developer={@current_developer}>
      <.header>
        {@page_title}
        <:subtitle>クライアント（テナント）の設定を管理します。</:subtitle>
      </.header>

      <.form for={@form} id="client-form" phx-change="validate" phx-submit="save">
        <.input field={@form[:name]} type="text" label="クライアント名" />
        <.input
          field={@form[:slug]}
          type="text"
          label="識別名"
          placeholder="ramen-taro"
        />
        <p class="mt-1 text-sm text-base-content/60">
          管理用の名前です。クライアントごとに重複しない値を付けます。<br /> 半角の英字（小文字）・数字・ハイフンが使えます。
        </p>
        <.input
          field={@form[:plan]}
          type="select"
          label="プラン"
          prompt="Choose a value"
          options={Ecto.Enum.values(AntPress.Platform.Client, :plan)}
        />
        <.input
          field={@form[:contact_notification_email]}
          type="email"
          label="問い合わせ通知先メールアドレス"
        />
        <.input
          field={@form[:webhook_url]}
          type="url"
          label="Webhook URL"
          placeholder="https://api.vercel.com/v1/integrations/deploy/..."
        />
        <.input
          field={@form[:status]}
          type="select"
          label="状態"
          prompt="Choose a value"
          options={Ecto.Enum.values(AntPress.Platform.Client, :status)}
        />
        <footer>
          <.button phx-disable-with="保存中..." variant="primary">保存</.button>
          <.button navigate={return_path(@current_developer, @return_to, @client)}>キャンセル</.button>
        </footer>
      </.form>
    </Layouts.app>
    """
  end

  @impl true
  def mount(params, _session, socket) do
    {:ok,
     socket
     |> assign(:return_to, return_to(params["return_to"]))
     |> apply_action(socket.assigns.live_action, params)}
  end

  defp return_to("show"), do: "show"
  defp return_to(_), do: "index"

  defp apply_action(socket, :edit, %{"id" => id}) do
    client = Platform.get_client!(socket.assigns.current_developer, id)

    socket
    |> assign(:page_title, "クライアントを編集")
    |> assign(:client, client)
    |> assign(:form, to_form(Platform.change_client(socket.assigns.current_developer, client)))
  end

  defp apply_action(socket, :new, _params) do
    client = %Client{developer_id: socket.assigns.current_developer.developer.id}

    socket
    |> assign(:page_title, "クライアントを追加")
    |> assign(:client, client)
    |> assign(:form, to_form(Platform.change_client(socket.assigns.current_developer, client)))
  end

  @impl true
  def handle_event("validate", %{"client" => client_params}, socket) do
    changeset =
      Platform.change_client(
        socket.assigns.current_developer,
        socket.assigns.client,
        client_params
      )

    {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"client" => client_params}, socket) do
    save_client(socket, socket.assigns.live_action, client_params)
  end

  defp save_client(socket, :edit, client_params) do
    case Platform.update_client(
           socket.assigns.current_developer,
           socket.assigns.client,
           client_params
         ) do
      {:ok, client} ->
        {:noreply,
         socket
         |> put_flash(:info, "クライアントを更新しました")
         |> push_navigate(
           to: return_path(socket.assigns.current_developer, socket.assigns.return_to, client)
         )}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp save_client(socket, :new, client_params) do
    case Platform.create_client(socket.assigns.current_developer, client_params) do
      {:ok, client} ->
        {:noreply,
         socket
         |> put_flash(:info, "クライアントを作成しました")
         |> push_navigate(
           to: return_path(socket.assigns.current_developer, socket.assigns.return_to, client)
         )}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp return_path(_scope, "index", _client), do: ~p"/clients"
  defp return_path(_scope, "show", client), do: ~p"/clients/#{client}"
end
