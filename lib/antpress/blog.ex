defmodule AntPress.Blog do
  @moduledoc """
  The Blog context.
  """

  import Ecto.Query, warn: false
  require Logger
  import Ecto.Changeset, only: [fetch_change: 2, add_error: 3]
  alias AntPress.Repo

  alias AntPress.Blog.{Article, Category}
  alias AntPress.Media.Image

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

  ## ─────────────────────────────────────────────
  ## 記事
  ## ─────────────────────────────────────────────

  @doc """
  Subscribes to scoped notifications about any article changes.

  The broadcasted messages match the pattern:

    * {:created, %Article{}}
    * {:updated, %Article{}}
    * {:deleted, %Article{}}

  """
  def subscribe_articles(%Scope{} = scope) do
    Phoenix.PubSub.subscribe(AntPress.PubSub, "client:#{scope.client.id}:blog_articles")
  end

  defp broadcast_article(%Scope{} = scope, message) do
    Phoenix.PubSub.broadcast(AntPress.PubSub, "client:#{scope.client.id}:blog_articles", message)
  end

  @doc """
  クライアントの記事一覧。**管理画面向けなので下書きも含む。**

  更新が新しいものを先に出す。公開日時順にしないのは、予約投稿（未来日時）が
  常に先頭に来てしまい、いま書いている記事が埋もれるため。

  ## 絞り込み（→ `docs/SCREENS.md` C3）

      list_articles(scope, filter: :draft)      # 下書き
      list_articles(scope, filter: :published)  # 公開済み（公開日時が過去）
      list_articles(scope, filter: :scheduled)  # 予約投稿（公開日時が未来）
      list_articles(scope, q: "ラーメン")        # タイトルの部分一致

  **「予約」は専用ステータスではない。** `status = :published` かつ
  `published_at` が未来のものを指す（→ `AntPress.Blog.Article`）。
  """
  def list_articles(%Scope{} = scope, opts \\ []) do
    Article
    |> where(client_id: ^scope.client.id)
    |> filter_articles(Keyword.get(opts, :filter, :all))
    |> search_articles(Keyword.get(opts, :q))
    |> order_by(desc: :updated_at, desc: :id)
    |> preload([:category, :thumbnail_image])
    |> Repo.all()
  end

  defp filter_articles(query, :draft), do: where(query, status: :draft)

  defp filter_articles(query, :published) do
    now = DateTime.utc_now(:second)
    where(query, [a], a.status == :published and a.published_at <= ^now)
  end

  defp filter_articles(query, :scheduled) do
    now = DateTime.utc_now(:second)
    where(query, [a], a.status == :published and a.published_at > ^now)
  end

  defp filter_articles(query, _all), do: query

  defp search_articles(query, nil), do: query
  defp search_articles(query, ""), do: query

  defp search_articles(query, q) do
    # 記事数が数十本の規模なので ILIKE で足りる。全文検索は入れない
    like = "%" <> escape_like(q) <> "%"
    where(query, [a], ilike(a.title, ^like))
  end

  # ILIKE のワイルドカードを打ち消す。"100%" で検索したときに
  # 全件一致にならないようにする
  defp escape_like(q) do
    q
    |> String.replace("\\", "\\\\")
    |> String.replace("%", "\\%")
    |> String.replace("_", "\\_")
  end

  @doc """
  記事の件数を絞り込みごとに数える。一覧のタブに出す。
  """
  def count_articles_by_filter(%Scope{} = scope) do
    Map.new([:all, :draft, :published, :scheduled], fn filter ->
      count =
        Article
        |> where(client_id: ^scope.client.id)
        |> filter_articles(filter)
        |> Repo.aggregate(:count)

      {filter, count}
    end)
  end

  @doc """
  記事を 1 件取得する。他クライアントの記事は取れない。
  """
  def get_article!(%Scope{} = scope, id) do
    Article
    |> where(client_id: ^scope.client.id, id: ^id)
    |> preload([:category, :thumbnail_image])
    |> Repo.one!()
  end

  @doc """
  記事を作成する。

  ⚠️ アドレス（`slug`）はシステムが割り当てる。attrs から渡しても無視される
  （→ `AntPress.Blog.Article`）。
  """
  def create_article(%Scope{} = scope, attrs) do
    with {:ok, %Article{} = article} <- insert_article(scope, attrs, 3) do
      broadcast_article(scope, {:created, article})
      {:ok, Repo.preload(article, [:category, :thumbnail_image])}
    end
  end

  # アドレスは 64 ビットの乱数なので衝突はまず起きないが、起きた場合に
  # ユーザーが直す手立てがない（入力欄が無いため）。**黙って作り直す。**
  defp insert_article(scope, attrs, attempts_left) do
    result =
      %Article{}
      |> Article.changeset(attrs, scope)
      |> validate_scoped_associations(scope)
      |> Repo.insert()

    case result do
      {:error, changeset} when attempts_left > 1 ->
        if slug_taken?(changeset) do
          Logger.warning("記事アドレスが衝突しました。作り直します client_id=#{scope.client.id}")
          insert_article(scope, attrs, attempts_left - 1)
        else
          result
        end

      _ ->
        result
    end
  end

  # `unique_constraint([:client_id, :slug])` は**先頭のフィールド**
  # （`:client_id`）にエラーを付ける。索引名まで見て、将来 client_id に
  # 別の一意制約が増えても誤って作り直さないようにする。
  # （実物の形: `{:client_id, {msg, [constraint: :unique, constraint_name: "..."]}}`）
  @slug_index "blog_articles_client_id_slug_index"

  defp slug_taken?(%Ecto.Changeset{errors: errors}) do
    Enum.any?(errors, fn
      {:client_id, {_msg, opts}} ->
        opts[:constraint] == :unique and opts[:constraint_name] == @slug_index

      _ ->
        false
    end)
  end

  @doc """
  記事を更新する。
  """
  def update_article(%Scope{} = scope, %Article{} = article, attrs) do
    true = article.client_id == scope.client.id

    with {:ok, %Article{} = article} <-
           article
           |> Article.changeset(attrs, scope)
           |> validate_scoped_associations(scope)
           |> Repo.update() do
      broadcast_article(scope, {:updated, article})
      {:ok, Repo.preload(article, [:category, :thumbnail_image], force: true)}
    end
  end

  @doc """
  記事を削除する。
  """
  def delete_article(%Scope{} = scope, %Article{} = article) do
    true = article.client_id == scope.client.id

    with {:ok, %Article{} = article} <- Repo.delete(article) do
      broadcast_article(scope, {:deleted, article})
      {:ok, article}
    end
  end

  @doc """
  記事フォーム用の changeset。
  """
  def change_article(%Scope{} = scope, %Article{} = article, attrs \\ %{}) do
    if article.client_id, do: true = article.client_id == scope.client.id

    Article.changeset(article, attrs, scope)
  end

  @doc """
  ⚠️ **カテゴリとサムネイル画像が同じクライアントのものかを検証する。**

  `category_id` / `thumbnail_image_id` はフォームから来る。画面には自分の
  カテゴリと画像しか出ないが、**リクエストは偽装できる。** 検証しないと
  他クライアントのカテゴリ名や画像を自社サイトに載せられてしまう
  （2 段テナントスコープの穴 → `CLAUDE.md`）。

  DB の外部キー制約は「存在するか」しか見ないので、これは別に必要。
  """
  def validate_scoped_associations(%Ecto.Changeset{} = changeset, %Scope{} = scope) do
    changeset
    |> validate_belongs_to_client(:category_id, Category, scope, "選べないカテゴリです")
    |> validate_belongs_to_client(:thumbnail_image_id, Image, scope, "選べない画像です")
  end

  defp validate_belongs_to_client(changeset, field, schema, scope, message) do
    case fetch_change(changeset, field) do
      # 変更なし、または未設定にした場合は検証不要
      :error -> changeset
      {:ok, nil} -> changeset
      {:ok, id} -> check_owner(changeset, field, schema, scope, id, message)
    end
  end

  defp check_owner(changeset, field, schema, scope, id, message) do
    owned? =
      schema
      |> where(id: ^id, client_id: ^scope.client.id)
      |> Repo.exists?()

    if owned?, do: changeset, else: add_error(changeset, field, message)
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
