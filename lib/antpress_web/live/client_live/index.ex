defmodule AntPressWeb.ClientLive.Index do
  @moduledoc """
  クライアント一覧（→ `docs/SCREENS.md` D3）。

  **削除は提供しない。** 契約終了は `status = :suspended` で表す
  （→ `docs/DECISIONS.md` 3.8）。停止したものが一覧に残り続けるので、
  稼働中 / 停止中で絞り込めるようにしている。
  """
  use AntPressWeb, :live_view

  alias AntPress.Platform

  @filters [all: "すべて", active: "稼働中", suspended: "停止中"]

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_developer={@current_developer}>
      <.header>
        クライアント
        <:actions>
          <.button variant="primary" navigate={~p"/clients/new"}>
            <.icon name="hero-plus" /> クライアントを追加
          </.button>
        </:actions>
      </.header>

      <div role="tablist" class="tabs tabs-box w-fit flex-wrap">
        <.link
          :for={{key, label} <- @filter_labels}
          role="tab"
          patch={~p"/clients?#{filter_params(key)}"}
          class={["tab", @filter == key && "tab-active"]}
        >
          {label}
          <span class="ml-1 text-xs opacity-60">{@counts[key]}</span>
        </.link>
      </div>

      <p :if={@counts[@filter] == 0} class="mt-10 text-center text-base-content/60">
        {empty_message(@filter)}
      </p>

      <.table
        :if={@counts[@filter] > 0}
        id="clients"
        rows={@streams.clients}
        row_click={fn {_id, client} -> JS.navigate(~p"/clients/#{client}") end}
      >
        <:col :let={{_id, client}} label="クライアント名">{client.name}</:col>
        <%!-- 狭い画面では主要な列だけ残す --%>
        <:col :let={{_id, client}} label="識別名" class="hidden sm:table-cell">
          {client.slug}
        </:col>
        <:col :let={{_id, client}} label="プラン">{plan_label(client.plan)}</:col>
        <:col :let={{_id, client}} label="問い合わせ通知先" class="hidden lg:table-cell">
          {client.contact_notification_email}
        </:col>
        <:col :let={{_id, client}} label="Webhook URL" class="hidden lg:table-cell">
          {webhook_label(client.webhook_url)}
        </:col>
        <:col :let={{_id, client}} label="状態">{status_label(client.status)}</:col>
        <:action :let={{_id, client}}>
          <div class="sr-only">
            <.link navigate={~p"/clients/#{client}"}>詳細</.link>
          </div>
          <.link navigate={~p"/clients/#{client}/edit"}>編集</.link>
        </:action>
      </.table>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Platform.subscribe_clients(socket.assigns.current_developer)
    end

    {:ok,
     socket
     |> assign(:page_title, "クライアント")
     |> assign(:filter_labels, @filters)
     |> stream(:clients, [])}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply,
     socket
     |> assign(:filter, parse_filter(params["filter"]))
     |> load_clients()}
  end

  @impl true
  def handle_info({type, %AntPress.Platform.Client{}}, socket)
      when type in [:created, :updated, :deleted] do
    {:noreply, load_clients(socket)}
  end

  defp load_clients(socket) do
    scope = socket.assigns.current_developer

    socket
    |> assign(:counts, Platform.count_clients_by_filter(scope))
    |> stream(:clients, Platform.list_clients(scope, filter: socket.assigns.filter), reset: true)
  end

  # 不正な値は「すべて」に落とす。URL を手で書き換えられても落ちないように
  defp parse_filter(value) do
    Enum.find_value(@filters, :all, fn {key, _} -> if to_string(key) == value, do: key end)
  end

  defp filter_params(:all), do: []
  defp filter_params(filter), do: [{"filter", filter}]

  defp empty_message(:active), do: "稼働中のクライアントはありません。"
  defp empty_message(:suspended), do: "停止中のクライアントはありません。"
  defp empty_message(_all), do: "まだクライアントがありません。"

  # ─── 表示用ヘルパー ─────────────────────────────
  defp plan_label(:basic), do: "基本"
  defp plan_label(:ai), do: "AI"
  defp plan_label(nil), do: "—"

  defp status_label(:active), do: "稼働中"
  defp status_label(:suspended), do: "停止中"
  defp status_label(nil), do: "—"

  # URL 全体を出すと表が崩れるので設定済みかどうかだけ示す
  defp webhook_label(nil), do: "未設定"
  defp webhook_label(""), do: "未設定"
  defp webhook_label(_url), do: "設定済み"
end
