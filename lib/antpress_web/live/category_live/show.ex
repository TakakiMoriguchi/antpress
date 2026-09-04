defmodule AntPressWeb.CategoryLive.Show do
  use AntPressWeb, :live_view

  alias AntPress.Blog

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <.header>
        {@category.name}
        <:subtitle>カテゴリの設定</:subtitle>
        <:actions>
          <.button navigate={~p"/client/categories"}>
            <.icon name="hero-arrow-left" />
          </.button>
          <.button
            variant="primary"
            navigate={~p"/client/categories/#{@category}/edit?return_to=show"}
          >
            <.icon name="hero-pencil-square" /> 編集
          </.button>
        </:actions>
      </.header>

      <.list>
        <:item title="カテゴリ名">{@category.name}</:item>
        <:item title="スラッグ">{@category.slug}</:item>
        <:item title="表示順">{@category.position}</:item>
      </.list>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    if connected?(socket) do
      Blog.subscribe_blog_categories(socket.assigns.current_user)
    end

    {:ok,
     socket
     |> assign(:page_title, "カテゴリ")
     |> assign(:category, Blog.get_category!(socket.assigns.current_user, id))}
  end

  @impl true
  def handle_info(
        {:updated, %AntPress.Blog.Category{id: id} = category},
        %{assigns: %{category: %{id: id}}} = socket
      ) do
    {:noreply, assign(socket, :category, category)}
  end

  def handle_info(
        {:deleted, %AntPress.Blog.Category{id: id}},
        %{assigns: %{category: %{id: id}}} = socket
      ) do
    {:noreply,
     socket
     |> put_flash(:error, "The current category was deleted.")
     |> push_navigate(to: ~p"/client/categories")}
  end

  def handle_info({type, %AntPress.Blog.Category{}}, socket)
      when type in [:created, :updated, :deleted] do
    {:noreply, socket}
  end
end
