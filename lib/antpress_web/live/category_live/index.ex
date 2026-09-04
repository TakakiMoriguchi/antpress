defmodule AntPressWeb.CategoryLive.Index do
  use AntPressWeb, :live_view

  alias AntPress.Blog

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <.header>
        カテゴリ
        <:actions>
          <.button variant="primary" navigate={~p"/client/categories/new"}>
            <.icon name="hero-plus" /> カテゴリを追加
          </.button>
        </:actions>
      </.header>

      <.table
        id="blog_categories"
        rows={@streams.blog_categories}
        row_click={fn {_id, category} -> JS.navigate(~p"/client/categories/#{category}") end}
      >
        <:col :let={{_id, category}} label="カテゴリ名">{category.name}</:col>
        <:col :let={{_id, category}} label="スラッグ">{category.slug}</:col>
        <:col :let={{_id, category}} label="表示順">{category.position}</:col>
        <:action :let={{_id, category}}>
          <div class="sr-only">
            <.link navigate={~p"/client/categories/#{category}"}>詳細</.link>
          </div>
          <.link navigate={~p"/client/categories/#{category}/edit"}>編集</.link>
        </:action>
        <:action :let={{id, category}}>
          <.link
            phx-click={JS.push("delete", value: %{id: category.id}) |> hide("##{id}")}
            data-confirm="このカテゴリを削除します。よろしいですか？"
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
      Blog.subscribe_blog_categories(socket.assigns.current_user)
    end

    {:ok,
     socket
     |> assign(:page_title, "カテゴリ")
     |> stream(:blog_categories, list_blog_categories(socket.assigns.current_user))}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    category = Blog.get_category!(socket.assigns.current_user, id)
    {:ok, _} = Blog.delete_category(socket.assigns.current_user, category)

    {:noreply, stream_delete(socket, :blog_categories, category)}
  end

  @impl true
  def handle_info({type, %AntPress.Blog.Category{}}, socket)
      when type in [:created, :updated, :deleted] do
    {:noreply,
     stream(socket, :blog_categories, list_blog_categories(socket.assigns.current_user),
       reset: true
     )}
  end

  defp list_blog_categories(current_user) do
    Blog.list_blog_categories(current_user)
  end
end
