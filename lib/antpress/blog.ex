defmodule AntPress.Blog do
  @moduledoc """
  The Blog context.
  """

  import Ecto.Query, warn: false
  alias AntPress.Repo

  alias AntPress.Blog.Category

  alias AntPress.Platform.Client
  alias AntPress.Accounts.Scope

  @doc """
  Subscribes to scoped notifications about any category changes.

  The broadcasted messages match the pattern:

    * {:created, %Category{}}
    * {:updated, %Category{}}
    * {:deleted, %Category{}}

  """
  def subscribe_blog_categories(%Scope{} = scope) do
    key = scope.client.id

    Phoenix.PubSub.subscribe(AntPress.PubSub, "client:#{key}:blog_categories")
  end

  defp broadcast_category(%Scope{} = scope, message) do
    key = scope.client.id

    Phoenix.PubSub.broadcast(AntPress.PubSub, "client:#{key}:blog_categories", message)
  end

  @doc """
  Returns the list of blog_categories.

  ## Examples

      iex> list_blog_categories(scope)
      [%Category{}, ...]

  """
  def list_blog_categories(%Scope{} = scope) do
    Category
    |> where(client_id: ^scope.client.id)
    |> order_by(asc: :position, asc: :name)
    |> Repo.all()
  end

  @doc """
  Gets a single category.

  Raises `Ecto.NoResultsError` if the Category does not exist.

  ## Examples

      iex> get_category!(scope, 123)
      %Category{}

      iex> get_category!(scope, 456)
      ** (Ecto.NoResultsError)

  """
  def get_category!(%Scope{} = scope, id) do
    Repo.get_by!(Category, id: id, client_id: scope.client.id)
  end

  @doc """
  Creates a category.

  ## Examples

      iex> create_category(scope, %{field: value})
      {:ok, %Category{}}

      iex> create_category(scope, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_category(%Scope{} = scope, attrs) do
    with {:ok, category = %Category{}} <-
           %Category{}
           |> Category.changeset(attrs, scope)
           |> Repo.insert() do
      broadcast_category(scope, {:created, category})
      {:ok, category}
    end
  end

  @doc """
  Updates a category.

  ## Examples

      iex> update_category(scope, category, %{field: new_value})
      {:ok, %Category{}}

      iex> update_category(scope, category, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_category(%Scope{} = scope, %Category{} = category, attrs) do
    true = category.client_id == scope.client.id

    with {:ok, category = %Category{}} <-
           category
           |> Category.changeset(attrs, scope)
           |> Repo.update() do
      broadcast_category(scope, {:updated, category})
      {:ok, category}
    end
  end

  @doc """
  Deletes a category.

  ## Examples

      iex> delete_category(scope, category)
      {:ok, %Category{}}

      iex> delete_category(scope, category)
      {:error, %Ecto.Changeset{}}

  """
  def delete_category(%Scope{} = scope, %Category{} = category) do
    true = category.client_id == scope.client.id

    with {:ok, category = %Category{}} <-
           Repo.delete(category) do
      broadcast_category(scope, {:deleted, category})
      {:ok, category}
    end
  end

  @doc """
  クライアント作成時に投入するカテゴリのプリセット。

  **空の状態からカテゴリを作らせない**ため（→ `docs/DECISIONS.md` 3.2）。
  業種横断で使えるものだけに絞る。使われないカテゴリが並ぶと選択の邪魔になる。
  """
  def category_presets do
    [
      %{name: "お知らせ", slug: "news", position: 0},
      %{name: "ブログ", slug: "blog", position: 1},
      %{name: "ニュース", slug: "press", position: 2}
    ]
  end

  @doc """
  クライアントにプリセットのカテゴリを投入する。

  **クライアント作成時に呼ぶ**（`Platform.create_client/2` から）。
  既にカテゴリがある場合は何もしない（冪等）。

  スコープではなく `%Client{}` を受け取る。作成直後で、まだそのクライアントに
  ログインできるユーザーが存在しないため。
  """
  def seed_categories(%Client{} = client) do
    if Repo.exists?(from c in Category, where: c.client_id == ^client.id) do
      {:ok, 0}
    else
      now = DateTime.utc_now(:second)

      rows =
        Enum.map(category_presets(), fn attrs ->
          # insert_all は binary_id に文字列形式の UUID を期待する
          # （bingenerate / dump! を使うと ChangeError になる）
          attrs
          |> Map.put(:id, Ecto.UUID.generate())
          |> Map.put(:client_id, client.id)
          |> Map.put(:inserted_at, now)
          |> Map.put(:updated_at, now)
        end)

      {count, _} = Repo.insert_all(Category, rows)
      {:ok, count}
    end
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking category changes.

  ## Examples

      iex> change_category(scope, category)
      %Ecto.Changeset{data: %Category{}}

  """
  def change_category(%Scope{} = scope, %Category{} = category, attrs \\ %{}) do
    true = category.client_id == scope.client.id

    Category.changeset(category, attrs, scope)
  end
end
