defmodule AntPressWeb.DeveloperAuth do
  use AntPressWeb, :verified_routes

  import Plug.Conn
  import Phoenix.Controller

  alias AntPress.Platform
  alias AntPress.Platform.Developer
  alias AntPress.Platform.Scope

  # Make the remember me cookie valid for 14 days. This should match
  # the session validity setting in DeveloperToken.
  @max_cookie_age_in_days 14
  @remember_me_cookie "_ant_press_web_developer_remember_me"
  @remember_me_options [
    sign: true,
    max_age: @max_cookie_age_in_days * 24 * 60 * 60,
    same_site: "Lax"
  ]

  # How old the session token should be before a new one is issued. When a request is made
  # with a session token older than this value, then a new session token will be created
  # and the session and remember-me cookies (if set) will be updated with the new token.
  # Lowering this value will result in more tokens being created by active users. Increasing
  # it will result in less time before a session token expires for a user to get issued a new
  # token. This can be set to a value greater than `@max_cookie_age_in_days` to disable
  # the reissuing of tokens completely.
  @session_reissue_age_in_days 7

  @doc """
  Logs the developer in.

  Redirects to the session's `:developer_return_to` path
  or falls back to the `signed_in_path/1`.
  """
  def log_in_developer(conn, developer, params \\ %{}) do
    developer_return_to = get_session(conn, :developer_return_to)

    conn
    |> create_or_extend_session(developer, params)
    |> delete_session(:developer_return_to)
    |> redirect(to: developer_return_to || signed_in_path(conn))
  end

  @doc """
  Logs the developer out.

  It clears all session data for safety. See renew_session.
  """
  def log_out_developer(conn, to \\ ~p"/") do
    developer_token = get_session(conn, :developer_token)
    developer_token && Platform.delete_developer_session_token(developer_token)

    if live_socket_id = get_session(conn, :live_socket_id) do
      AntPressWeb.Endpoint.broadcast(live_socket_id, "disconnect", %{})
    end

    conn
    |> renew_session(nil)
    |> delete_resp_cookie(@remember_me_cookie, @remember_me_options)
    # ⚠️ 行き先を選べるようにしてある。停止でログアウトさせる場合は
    # ログイン画面へ送る（トップに落とすと何が起きたのか分からない）
    |> redirect(to: to)
  end

  @doc """
  Authenticates the developer by looking into the session and remember me token.

  Will reissue the session token if it is older than the configured age.
  """
  def fetch_current_developer_for_developer(conn, _opts) do
    with {token, conn} <- ensure_developer_token(conn),
         {developer, token_inserted_at} <- Platform.get_developer_by_session_token(token) do
      conn
      |> assign(:current_developer, Scope.for_developer(developer))
      |> maybe_reissue_developer_session_token(developer, token_inserted_at)
    else
      nil -> assign(conn, :current_developer, Scope.for_developer(nil))
    end
  end

  defp ensure_developer_token(conn) do
    if token = get_session(conn, :developer_token) do
      {token, conn}
    else
      conn = fetch_cookies(conn, signed: [@remember_me_cookie])

      if token = conn.cookies[@remember_me_cookie] do
        {token, conn |> put_token_in_session(token) |> put_session(:developer_remember_me, true)}
      else
        nil
      end
    end
  end

  # Reissue the session token if it is older than the configured reissue age.
  defp maybe_reissue_developer_session_token(conn, developer, token_inserted_at) do
    token_age = DateTime.diff(DateTime.utc_now(:second), token_inserted_at, :day)

    if token_age >= @session_reissue_age_in_days do
      create_or_extend_session(conn, developer, %{})
    else
      conn
    end
  end

  # This function is the one responsible for creating session tokens
  # and storing them safely in the session and cookies. It may be called
  # either when logging in, during sudo mode, or to renew a session which
  # will soon expire.
  #
  # When the session is created, rather than extended, the renew_session
  # function will clear the session to avoid fixation attacks. See the
  # renew_session function to customize this behaviour.
  defp create_or_extend_session(conn, developer, params) do
    token = Platform.generate_developer_session_token(developer)
    remember_me = get_session(conn, :developer_remember_me)

    conn
    |> renew_session(developer)
    |> put_token_in_session(token)
    |> maybe_write_remember_me_cookie(token, params, remember_me)
  end

  # Do not renew session if the developer is already logged in
  # to prevent CSRF errors or data being lost in tabs that are still open
  defp renew_session(conn, developer)
       when conn.assigns.current_developer.developer.id == developer.id do
    conn
  end

  # This function renews the session ID and erases the whole
  # session to avoid fixation attacks. If there is any data
  # in the session you may want to preserve after log in/log out,
  # you must explicitly fetch the session data before clearing
  # and then immediately set it after clearing, for example:
  #
  #     defp renew_session(conn, _developer) do
  #       delete_csrf_token()
  #       preferred_locale = get_session(conn, :preferred_locale)
  #
  #       conn
  #       |> configure_session(renew: true)
  #       |> clear_session()
  #       |> put_session(:preferred_locale, preferred_locale)
  #     end
  #
  defp renew_session(conn, _developer) do
    delete_csrf_token()

    conn
    |> configure_session(renew: true)
    |> clear_session()
  end

  defp maybe_write_remember_me_cookie(conn, token, %{"remember_me" => "true"}, _),
    do: write_remember_me_cookie(conn, token)

  defp maybe_write_remember_me_cookie(conn, token, _params, true),
    do: write_remember_me_cookie(conn, token)

  defp maybe_write_remember_me_cookie(conn, _token, _params, _), do: conn

  defp write_remember_me_cookie(conn, token) do
    conn
    |> put_session(:developer_remember_me, true)
    |> put_resp_cookie(@remember_me_cookie, token, @remember_me_options)
  end

  defp put_token_in_session(conn, token) do
    conn
    |> put_session(:developer_token, token)
    |> put_session(:live_socket_id, developer_session_topic(token))
  end

  @doc """
  Disconnects existing sockets for the given tokens.
  """
  def disconnect_sessions(tokens) do
    Enum.each(tokens, fn %{token: token} ->
      AntPressWeb.Endpoint.broadcast(developer_session_topic(token), "disconnect", %{})
    end)
  end

  defp developer_session_topic(token), do: "developers_sessions:#{Base.url_encode64(token)}"

  @doc """
  Handles mounting and authenticating the current_developer in LiveViews.

  ## `on_mount` arguments

    * `:mount_current_developer` - Assigns current_developer
      to socket assigns based on developer_token, or nil if
      there's no developer_token or no matching developer.

    * `:require_authenticated` - Authenticates the developer from the session,
      and assigns the current_developer to socket assigns based
      on developer_token.
      Redirects to login page if there's no logged developer.

  ## Examples

  Use the `on_mount` lifecycle macro in LiveViews to mount or authenticate
  the `current_developer`:

      defmodule AntPressWeb.PageLive do
        use AntPressWeb, :live_view

        on_mount {AntPressWeb.DeveloperAuth, :mount_current_developer}
        ...
      end

  Or use the `live_session` of your router to invoke the on_mount callback:

      live_session :authenticated, on_mount: [{AntPressWeb.DeveloperAuth, :require_authenticated}] do
        live "/profile", ProfileLive, :index
      end
  """
  def on_mount(:mount_current_developer, _params, session, socket) do
    {:cont, mount_current_developer(socket, session)}
  end

  def on_mount(:require_authenticated, _params, session, socket) do
    socket = mount_current_developer(socket, session)
    developer = socket.assigns.current_developer && socket.assigns.current_developer.developer

    cond do
      is_nil(developer) ->
        {:halt, redirect_to_login(socket, "このページを表示するにはログインが必要です")}

      # ⚠️ plug 側だけでは足りない。LiveView は WebSocket で繋ぎ直すので、
      # ここを漏らすと停止後も画面が動き続ける
      not Platform.active?(developer) ->
        {:halt, redirect_to_login(socket, "ご利用が停止されています。運営者にお問い合わせください")}

      true ->
        {:cont, socket}
    end
  end

  # admin だけが入れる画面に使う（→ docs/SCREENS.md P1〜P4）。
  #
  # ⚠️ developer が admin の画面に入れると、**他の developer とその
  # クライアント全部が見えてしまう。**
  def on_mount(:require_admin, params, session, socket) do
    case on_mount(:require_authenticated, params, session, socket) do
      {:cont, socket} ->
        if Developer.admin?(socket.assigns.current_developer.developer) do
          {:cont, socket}
        else
          {:halt,
           socket
           |> Phoenix.LiveView.put_flash(:error, "この画面を表示する権限がありません")
           |> Phoenix.LiveView.redirect(to: ~p"/clients")}
        end

      halted ->
        halted
    end
  end

  def on_mount(:require_sudo_mode, _params, session, socket) do
    socket = mount_current_developer(socket, session)

    if Platform.sudo_mode?(socket.assigns.current_developer.developer, -10) do
      {:cont, socket}
    else
      socket =
        socket
        |> Phoenix.LiveView.put_flash(:error, "この操作にはログインし直しが必要です")
        |> Phoenix.LiveView.redirect(to: ~p"/developers/log-in")

      {:halt, socket}
    end
  end

  defp redirect_to_login(socket, message) do
    socket
    |> Phoenix.LiveView.put_flash(:error, message)
    |> Phoenix.LiveView.redirect(to: ~p"/developers/log-in")
  end

  defp mount_current_developer(socket, session) do
    Phoenix.Component.assign_new(socket, :current_developer, fn ->
      {developer, _} =
        if developer_token = session["developer_token"] do
          Platform.get_developer_by_session_token(developer_token)
        end || {nil, nil}

      Scope.for_developer(developer)
    end)
  end

  @doc "Returns the path to redirect to after log in."
  # the developer was already logged in, redirect to settings
  # developer / admin の主画面はクライアント管理（→ docs/SCREENS.md D3）。
  #
  # ⚠️ ログイン処理の時点では current_developer がまだ未設定（認証前にプラグが
  #    nil を入れている）なので、パターンマッチだけでは第 1 節に一致しない。
  #    フォールバックも同じ行き先にしておく必要がある。
  def signed_in_path(%Plug.Conn{
        assigns: %{current_developer: %Scope{developer: %Platform.Developer{}}}
      }),
      do: ~p"/clients"

  def signed_in_path(_), do: ~p"/clients"

  @doc """
  Plug for routes that require the developer to be authenticated.
  """
  def require_authenticated_developer(conn, _opts) do
    developer = conn.assigns.current_developer && conn.assigns.current_developer.developer

    cond do
      is_nil(developer) ->
        conn
        |> put_flash(:error, "このページを表示するにはログインが必要です")
        |> maybe_store_return_to()
        |> redirect(to: ~p"/developers/log-in")
        |> halt()

      # ⚠️ **既存のセッションもここで止まる。** 新規ログインだけを塞ぐと、
      # 停止した developer がセッションの有効期間（14 日）ぶん使い続けられる
      not Platform.active?(developer) ->
        conn
        |> put_flash(:error, "ご利用が停止されています。運営者にお問い合わせください")
        |> log_out_developer(~p"/developers/log-in")
        |> halt()

      true ->
        conn
    end
  end

  defp maybe_store_return_to(%{method: "GET"} = conn) do
    put_session(conn, :developer_return_to, current_path(conn))
  end

  defp maybe_store_return_to(conn), do: conn
end
