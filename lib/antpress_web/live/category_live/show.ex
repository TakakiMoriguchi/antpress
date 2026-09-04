defmodule AntPressWeb.CategoryLive.Show do
  use AntPressWeb, :live_view

  alias AntPress.Blog

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <.header>
        Category {@category.id}
        <:subtitle>This is a category record from your database.</:subtitle>
        <:actions>
          <.button navigate={~p"/client/categories"}>
            <.icon name="hero-arrow-left" />
          </.button>
          <.button
            variant="primary"
            navigate={~p"/client/categories/#{@category}/edit?return_to=show"}
          >
            <.icon name="hero-pencil-square" /> Edit category
          </.button>
        </:actions>
      </.header>

      <.list>
        <:item title="Name">{@category.name}</:item>
        <:item title="Slug">{@category.slug}</:item>
        <:item title="Position">{@category.position}</:item>
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
     |> assign(:page_title, "Show Category")
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
