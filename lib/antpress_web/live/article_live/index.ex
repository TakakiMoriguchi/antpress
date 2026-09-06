defmodule AntPressWeb.ArticleLive.Index do
  @moduledoc """
  記事一覧（→ `docs/SCREENS.md` C3）。**ログイン後の着地点。**

  下書き / 公開 / 予約 で絞り込み、タイトルで検索する。

  「予約」は専用ステータスではなく `status = :published` かつ
  `published_at` が未来のもの（→ `AntPress.Blog.Article`）。
  """
  use AntPressWeb, :live_view

  alias AntPress.Blog
  alias AntPress.Blog.Article
  alias AntPressWeb.JST

  @filters [all: "すべて", draft: "下書き", published: "公開", scheduled: "予約"]

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <.header>
        記事
        <:actions>
          <.button variant="primary" navigate={~p"/client/articles/new"}>
            <.icon name="hero-plus" /> 記事を書く
          </.button>
        </:actions>
      </.header>

      <div class="flex flex-wrap items-center justify-between gap-4">
        <%!-- 狭い画面では全幅・等分。左に寄せると余白が間延びする --%>
        <div role="tablist" class="tabs tabs-box w-full flex-wrap sm:w-auto">
          <.link
            :for={{key, label} <- @filter_labels}
            role="tab"
            patch={~p"/client/articles?#{query_params(key, @q)}"}
            class={["tab flex-1 sm:flex-none", @filter == key && "tab-active"]}
          >
            {label}
            <span class="ml-1 text-xs opacity-60">{@counts[key]}</span>
          </.link>
        </div>

        <form
          id="article-search"
          phx-change="search"
          phx-submit="search"
          class="flex w-full items-center gap-2 sm:w-auto"
        >
          <input
            type="search"
            name="q"
            value={@q}
            placeholder="タイトルで検索"
            phx-debounce="300"
            aria-label="タイトルで検索"
            class="input w-full sm:w-64"
          />
        </form>
      </div>

      <p :if={@articles == []} class="mt-10 text-center text-base-content/60">
        {empty_message(@filter, @q)}
      </p>

      <div :if={@articles != []} class="mt-6 overflow-x-auto">
        <table class="table">
          <thead>
            <tr>
              <th class="w-16"></th>
              <th>タイトル</th>
              <%!-- 狭い画面では主要な列だけ残す。横スクロールさせない --%>
              <th class="hidden sm:table-cell">カテゴリ</th>
              <th>状態</th>
              <th class="hidden md:table-cell">公開日時</th>
              <th class="w-0"><span class="sr-only">操作</span></th>
            </tr>
          </thead>
          <tbody id="articles" phx-update="stream">
            <tr :for={{dom_id, article} <- @streams.articles} id={dom_id}>
              <td>
                <img
                  :if={article.thumbnail_image}
                  src={AntPress.Media.public_url(article.thumbnail_image)}
                  alt={article.thumbnail_image.alt_text || ""}
                  loading="lazy"
                  class="size-12 rounded bg-base-200 object-cover"
                />
                <div
                  :if={is_nil(article.thumbnail_image)}
                  class="size-12 rounded bg-base-200"
                  aria-hidden="true"
                />
              </td>
              <td>
                <.link
                  navigate={~p"/client/articles/#{article}/edit"}
                  class="font-medium hover:underline"
                >
                  {article.title}
                </.link>
                <p class="text-xs text-base-content/60">/{article.slug}</p>
              </td>
              <td class="hidden text-sm sm:table-cell">{category_label(article)}</td>
              <td>
                <span class={["badge badge-sm", state_class(article)]}>{state_label(article)}</span>
              </td>
              <td class="hidden text-sm whitespace-nowrap md:table-cell">
                {published_at_label(article)}
              </td>
              <td class="whitespace-nowrap font-semibold">
                <div class="flex gap-4">
                  <.link navigate={~p"/client/articles/#{article}/edit"}>編集</.link>
                  <.link
                    phx-click={JS.push("delete", value: %{id: article.id})}
                    data-confirm="この記事を削除します。よろしいですか？"
                    class="text-error"
                  >
                    削除
                  </.link>
                </div>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Blog.subscribe_articles(socket.assigns.current_user)
    end

    {:ok,
     socket
     |> assign(:page_title, "記事")
     |> assign(:filter_labels, @filters)
     |> stream(:articles, [])}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, socket |> assign_query(params) |> load_articles()}
  end

  @impl true
  def handle_event("search", %{"q" => q}, socket) do
    {:noreply,
     push_patch(socket, to: ~p"/client/articles?#{query_params(socket.assigns.filter, q)}")}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    scope = socket.assigns.current_user
    article = Blog.get_article!(scope, id)
    {:ok, _} = Blog.delete_article(scope, article)

    {:noreply,
     socket
     |> put_flash(:info, "記事を削除しました")
     |> load_articles()}
  end

  @impl true
  def handle_info({type, %Article{}}, socket) when type in [:created, :updated, :deleted] do
    {:noreply, load_articles(socket)}
  end

  defp assign_query(socket, params) do
    socket
    |> assign(:filter, parse_filter(params["filter"]))
    |> assign(:q, params["q"] || "")
  end

  defp load_articles(socket) do
    scope = socket.assigns.current_user
    articles = Blog.list_articles(scope, filter: socket.assigns.filter, q: socket.assigns.q)

    socket
    |> assign(:articles, articles)
    |> assign(:counts, Blog.count_articles_by_filter(scope))
    |> stream(:articles, articles, reset: true)
  end

  # 不正な値は「すべて」に落とす。URL を手で書き換えられても落ちないように
  defp parse_filter(value) do
    Enum.find_value(@filters, :all, fn {key, _} -> if to_string(key) == value, do: key end)
  end

  defp query_params(filter, q) do
    []
    |> then(fn acc -> if filter == :all, do: acc, else: [{"filter", filter} | acc] end)
    |> then(fn acc -> if q in [nil, ""], do: acc, else: [{"q", q} | acc] end)
  end

  defp empty_message(_filter, q) when q not in [nil, ""], do: "「#{q}」に一致する記事はありません。"
  defp empty_message(:draft, _q), do: "下書きはありません。"
  defp empty_message(:published, _q), do: "公開済みの記事はありません。"
  defp empty_message(:scheduled, _q), do: "予約投稿はありません。"
  defp empty_message(_all, _q), do: "まだ記事がありません。"

  defp category_label(%Article{category: nil}), do: "未分類"
  defp category_label(%Article{category: category}), do: category.name

  @doc """
  記事の状態表示。**予約はステータスではなく公開日時から導く。**
  """
  def state_label(%Article{status: :draft}), do: "下書き"

  def state_label(%Article{status: :published, published_at: at}) do
    if at && DateTime.after?(at, DateTime.utc_now()), do: "予約", else: "公開"
  end

  defp state_class(%Article{status: :draft}), do: "badge-ghost"

  defp state_class(%Article{} = article) do
    if state_label(article) == "予約", do: "badge-warning", else: "badge-success"
  end

  # ⚠️ 下書きは公開日時を出さない。
  #
  # 一度公開してから下書きに戻すと `published_at` は残るので、そのまま
  # 表示すると「下書きなのに公開日時が入っている」ことになる。
  # また `—` だと「データが無い」ように見えて、公開していないだけなのか
  # 入力し忘れなのか分からない。
  defp published_at_label(%Article{status: :draft}), do: "未公開"
  defp published_at_label(%Article{published_at: nil}), do: "未公開"

  # ⚠️ 保存は UTC、表示は日本時間（→ AntPressWeb.JST）
  defp published_at_label(%Article{published_at: at}), do: JST.format(at)
end
