defmodule AntPressWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use AntPressWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://phoenix.hexdocs.pm/scopes.html)"

  # phx.gen.auth を --assign-key current_developer で実行したため、
  # 生成された LiveView はこの名前で渡してくる。
  # クライアント側の認証を生成したら current_user も追加する。
  attr :current_developer, :map,
    default: nil,
    doc: "ログイン中の developer（role: admin を含む）"

  attr :current_user, :map,
    default: nil,
    doc: "ログイン中のクライアント側ユーザー（owner / staff）"

  slot :inner_block, required: true

  def app(assigns) do
    # ⚠️ ナビは **root.html.heex ではなくここ**に置く。
    #
    # root.html.heex は conn の assign を見るが、`current_user` と
    # `current_developer` を入れる plug は**どちらもすべてのリクエストで走る。**
    # そのため両方でログインしていると、クライアント側の画面でも
    # developer のナビが出て、記事・カテゴリ・画像へ移動できなくなる
    # （実際にそうなった）。
    #
    # ここなら「どちらの assign を渡されたか」＝ページ自身がどちら側かで決まる。
    #
    # Phoenix の既定ヘッダー（ロゴ・Website・GitHub・Get Started）は削除した。
    ~H"""
    <nav
      :if={@current_developer || @current_user}
      class="navbar border-b border-base-300 px-4 sm:px-6 lg:px-8"
    >
      <div class="flex-1">
        <.link
          :if={@current_developer}
          navigate={~p"/clients"}
          class="text-lg font-semibold"
        >
          antpress
        </.link>
        <.link
          :if={@current_user}
          navigate={~p"/client/articles"}
          class="text-lg font-semibold"
        >
          antpress
        </.link>
      </div>

      <div class="flex-none">
        <ul class="menu menu-horizontal items-center gap-1">
          <%= if @current_developer do %>
            <li><.link navigate={~p"/clients"}>クライアント</.link></li>
            <li><.link href={~p"/developers/settings"}>アカウント</.link></li>
            <li><.link href={~p"/developers/log-out"} method="delete">ログアウト</.link></li>
          <% else %>
            <li><.link navigate={~p"/client/articles"}>記事</.link></li>
            <li><.link navigate={~p"/client/categories"}>カテゴリ</.link></li>
            <li><.link navigate={~p"/client/images"}>画像</.link></li>
            <li><.link href={~p"/client/settings"}>アカウント</.link></li>
            <li><.link href={~p"/client/log-out"} method="delete">ログアウト</.link></li>
          <% end %>
        </ul>
      </div>
    </nav>

    <main class="px-4 py-8 sm:px-6 lg:px-8">
      <div class="mx-auto max-w-6xl space-y-4">
        {render_slot(@inner_block)}
      </div>
    </main>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <%!-- ⚠️ 接続断の通知は自動で閉じない。状態が続いている間は出したまま --%>
      <.flash
        id="client-error"
        kind={:error}
        autoclose={false}
        title={gettext("We can't find the internet")}
        phx-disconnected={
          show(".phx-client-error #client-error")
          |> JS.remove_attribute("hidden", to: ".phx-client-error #client-error")
        }
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        autoclose={false}
        title={gettext("Something went wrong!")}
        phx-disconnected={
          show(".phx-server-error #server-error")
          |> JS.remove_attribute("hidden", to: ".phx-server-error #server-error")
        }
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 [[data-theme-source=system]_&]:!left-0 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
