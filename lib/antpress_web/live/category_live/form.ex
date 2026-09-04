defmodule AntPressWeb.CategoryLive.Form do
  use AntPressWeb, :live_view

  alias AntPress.Blog
  alias AntPress.Blog.Category

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <.header>
        {@page_title}
        <:subtitle>Use this form to manage category records in your database.</:subtitle>
      </.header>

      <.form for={@form} id="category-form" phx-change="validate" phx-submit="save">
        <.input field={@form[:name]} type="text" label="カテゴリ名" />
        <.input
          field={@form[:slug]}
          type="text"
          label="スラッグ"
          placeholder="news"
        />
        <.input field={@form[:position]} type="number" label="表示順" />
        <footer>
          <.button phx-disable-with="保存中..." variant="primary">保存</.button>
          <.button navigate={return_path(@current_user, @return_to, @category)}>Cancel</.button>
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
    category = Blog.get_category!(socket.assigns.current_user, id)

    socket
    |> assign(:page_title, "カテゴリを編集")
    |> assign(:category, category)
    |> assign(:form, to_form(Blog.change_category(socket.assigns.current_user, category)))
  end

  defp apply_action(socket, :new, _params) do
    category = %Category{client_id: socket.assigns.current_user.client.id}

    socket
    |> assign(:page_title, "カテゴリを追加")
    |> assign(:category, category)
    |> assign(:form, to_form(Blog.change_category(socket.assigns.current_user, category)))
  end

  @impl true
  def handle_event("validate", %{"category" => category_params}, socket) do
    changeset =
      Blog.change_category(socket.assigns.current_user, socket.assigns.category, category_params)

    {:noreply, assign(socket, form: to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"category" => category_params}, socket) do
    save_category(socket, socket.assigns.live_action, category_params)
  end

  defp save_category(socket, :edit, category_params) do
    case Blog.update_category(
           socket.assigns.current_user,
           socket.assigns.category,
           category_params
         ) do
      {:ok, category} ->
        {:noreply,
         socket
         |> put_flash(:info, "Category updated successfully")
         |> push_navigate(
           to: return_path(socket.assigns.current_user, socket.assigns.return_to, category)
         )}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp save_category(socket, :new, category_params) do
    case Blog.create_category(socket.assigns.current_user, category_params) do
      {:ok, category} ->
        {:noreply,
         socket
         |> put_flash(:info, "Category created successfully")
         |> push_navigate(
           to: return_path(socket.assigns.current_user, socket.assigns.return_to, category)
         )}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp return_path(_scope, "index", _category), do: ~p"/client/categories"
  defp return_path(_scope, "show", category), do: ~p"/client/categories/#{category}"
end
