defmodule AntPressWeb.DeveloperAuthTest do
  use AntPressWeb.ConnCase, async: true

  alias Phoenix.LiveView
  alias AntPress.Platform
  alias AntPress.Platform.Scope
  alias AntPressWeb.DeveloperAuth

  import AntPress.PlatformFixtures

  @remember_me_cookie "_ant_press_web_developer_remember_me"
  @remember_me_cookie_max_age 60 * 60 * 24 * 14

  setup %{conn: conn} do
    conn =
      conn
      |> Map.replace!(:secret_key_base, AntPressWeb.Endpoint.config(:secret_key_base))
      |> init_test_session(%{})

    %{developer: %{developer_fixture() | authenticated_at: DateTime.utc_now(:second)}, conn: conn}
  end

  describe "log_in_developer/3" do
    test "stores the developer token in the session", %{conn: conn, developer: developer} do
      conn = DeveloperAuth.log_in_developer(conn, developer)
      assert token = get_session(conn, :developer_token)

      assert get_session(conn, :live_socket_id) ==
               "developers_sessions:#{Base.url_encode64(token)}"

      assert redirected_to(conn) == ~p"/clients"
      assert Platform.get_developer_by_session_token(token)
    end

    test "clears everything previously stored in the session", %{conn: conn, developer: developer} do
      conn =
        conn |> put_session(:to_be_removed, "value") |> DeveloperAuth.log_in_developer(developer)

      refute get_session(conn, :to_be_removed)
    end

    test "keeps session when re-authenticating", %{conn: conn, developer: developer} do
      conn =
        conn
        |> assign(:current_developer, Scope.for_developer(developer))
        |> put_session(:to_be_removed, "value")
        |> DeveloperAuth.log_in_developer(developer)

      assert get_session(conn, :to_be_removed)
    end

    test "clears session when developer does not match when re-authenticating", %{
      conn: conn,
      developer: developer
    } do
      other_developer = developer_fixture()

      conn =
        conn
        |> assign(:current_developer, Scope.for_developer(other_developer))
        |> put_session(:to_be_removed, "value")
        |> DeveloperAuth.log_in_developer(developer)

      refute get_session(conn, :to_be_removed)
    end

    test "redirects to the configured path", %{conn: conn, developer: developer} do
      conn =
        conn
        |> put_session(:developer_return_to, "/hello")
        |> DeveloperAuth.log_in_developer(developer)

      assert redirected_to(conn) == "/hello"
    end

    test "clears the return-to path from the session after logging in", %{
      conn: conn,
      developer: developer
    } do
      conn =
        conn
        |> assign(:current_developer, Scope.for_developer(developer))
        |> put_session(:developer_return_to, "/hello")
        |> DeveloperAuth.log_in_developer(developer)

      assert redirected_to(conn) == "/hello"
      refute get_session(conn, :developer_return_to)
    end

    test "writes a cookie if remember_me is configured", %{conn: conn, developer: developer} do
      conn =
        conn
        |> fetch_cookies()
        |> DeveloperAuth.log_in_developer(developer, %{"remember_me" => "true"})

      assert get_session(conn, :developer_token) == conn.cookies[@remember_me_cookie]
      assert get_session(conn, :developer_remember_me) == true

      assert %{value: signed_token, max_age: max_age} = conn.resp_cookies[@remember_me_cookie]
      assert signed_token != get_session(conn, :developer_token)
      assert max_age == @remember_me_cookie_max_age
    end

    test "redirects to client list when developer is already logged in", %{
      conn: conn,
      developer: developer
    } do
      conn =
        conn
        |> assign(:current_developer, Scope.for_developer(developer))
        |> DeveloperAuth.log_in_developer(developer)

      assert redirected_to(conn) == ~p"/clients"
    end

    test "writes a cookie if remember_me was set in previous session", %{
      conn: conn,
      developer: developer
    } do
      conn =
        conn
        |> fetch_cookies()
        |> DeveloperAuth.log_in_developer(developer, %{"remember_me" => "true"})

      assert get_session(conn, :developer_token) == conn.cookies[@remember_me_cookie]
      assert get_session(conn, :developer_remember_me) == true

      conn =
        conn
        |> recycle()
        |> Map.replace!(:secret_key_base, AntPressWeb.Endpoint.config(:secret_key_base))
        |> fetch_cookies()
        |> init_test_session(%{developer_remember_me: true})

      # the conn is already logged in and has the remember_me cookie set,
      # now we log in again and even without explicitly setting remember_me,
      # the cookie should be set again
      conn = conn |> DeveloperAuth.log_in_developer(developer, %{})
      assert %{value: signed_token, max_age: max_age} = conn.resp_cookies[@remember_me_cookie]
      assert signed_token != get_session(conn, :developer_token)
      assert max_age == @remember_me_cookie_max_age
      assert get_session(conn, :developer_remember_me) == true
    end
  end

  describe "logout_developer/1" do
    test "erases session and cookies", %{conn: conn, developer: developer} do
      developer_token = Platform.generate_developer_session_token(developer)

      conn =
        conn
        |> put_session(:developer_token, developer_token)
        |> put_req_cookie(@remember_me_cookie, developer_token)
        |> fetch_cookies()
        |> DeveloperAuth.log_out_developer()

      refute get_session(conn, :developer_token)
      refute conn.cookies[@remember_me_cookie]
      assert %{max_age: 0} = conn.resp_cookies[@remember_me_cookie]
      assert redirected_to(conn) == ~p"/"
      refute Platform.get_developer_by_session_token(developer_token)
    end

    test "broadcasts to the given live_socket_id", %{conn: conn} do
      live_socket_id = "developers_sessions:abcdef-token"
      AntPressWeb.Endpoint.subscribe(live_socket_id)

      conn
      |> put_session(:live_socket_id, live_socket_id)
      |> DeveloperAuth.log_out_developer()

      assert_receive %Phoenix.Socket.Broadcast{event: "disconnect", topic: ^live_socket_id}
    end

    test "works even if developer is already logged out", %{conn: conn} do
      conn = conn |> fetch_cookies() |> DeveloperAuth.log_out_developer()
      refute get_session(conn, :developer_token)
      assert %{max_age: 0} = conn.resp_cookies[@remember_me_cookie]
      assert redirected_to(conn) == ~p"/"
    end
  end

  describe "fetch_current_developer_for_developer/2" do
    test "authenticates developer from session", %{conn: conn, developer: developer} do
      developer_token = Platform.generate_developer_session_token(developer)

      conn =
        conn
        |> put_session(:developer_token, developer_token)
        |> DeveloperAuth.fetch_current_developer_for_developer([])

      assert conn.assigns.current_developer.developer.id == developer.id

      assert conn.assigns.current_developer.developer.authenticated_at ==
               developer.authenticated_at

      assert get_session(conn, :developer_token) == developer_token
    end

    test "authenticates developer from cookies", %{conn: conn, developer: developer} do
      logged_in_conn =
        conn
        |> fetch_cookies()
        |> DeveloperAuth.log_in_developer(developer, %{"remember_me" => "true"})

      developer_token = logged_in_conn.cookies[@remember_me_cookie]
      %{value: signed_token} = logged_in_conn.resp_cookies[@remember_me_cookie]

      conn =
        conn
        |> put_req_cookie(@remember_me_cookie, signed_token)
        |> DeveloperAuth.fetch_current_developer_for_developer([])

      assert conn.assigns.current_developer.developer.id == developer.id

      assert conn.assigns.current_developer.developer.authenticated_at ==
               developer.authenticated_at

      assert get_session(conn, :developer_token) == developer_token
      assert get_session(conn, :developer_remember_me)

      assert get_session(conn, :live_socket_id) ==
               "developers_sessions:#{Base.url_encode64(developer_token)}"
    end

    test "does not authenticate if data is missing", %{conn: conn, developer: developer} do
      _ = Platform.generate_developer_session_token(developer)
      conn = DeveloperAuth.fetch_current_developer_for_developer(conn, [])
      refute get_session(conn, :developer_token)
      refute conn.assigns.current_developer
    end

    test "reissues a new token after a few days and refreshes cookie", %{
      conn: conn,
      developer: developer
    } do
      logged_in_conn =
        conn
        |> fetch_cookies()
        |> DeveloperAuth.log_in_developer(developer, %{"remember_me" => "true"})

      token = logged_in_conn.cookies[@remember_me_cookie]
      %{value: signed_token} = logged_in_conn.resp_cookies[@remember_me_cookie]

      offset_developer_token(token, -10, :day)
      {developer, _} = Platform.get_developer_by_session_token(token)

      conn =
        conn
        |> put_session(:developer_token, token)
        |> put_session(:developer_remember_me, true)
        |> put_req_cookie(@remember_me_cookie, signed_token)
        |> DeveloperAuth.fetch_current_developer_for_developer([])

      assert conn.assigns.current_developer.developer.id == developer.id

      assert conn.assigns.current_developer.developer.authenticated_at ==
               developer.authenticated_at

      assert new_token = get_session(conn, :developer_token)
      assert new_token != token
      assert %{value: new_signed_token, max_age: max_age} = conn.resp_cookies[@remember_me_cookie]
      assert new_signed_token != signed_token
      assert max_age == @remember_me_cookie_max_age
    end
  end

  describe "on_mount :mount_current_developer" do
    setup %{conn: conn} do
      %{conn: DeveloperAuth.fetch_current_developer_for_developer(conn, [])}
    end

    test "assigns current_developer based on a valid developer_token", %{
      conn: conn,
      developer: developer
    } do
      developer_token = Platform.generate_developer_session_token(developer)
      session = conn |> put_session(:developer_token, developer_token) |> get_session()

      {:cont, updated_socket} =
        DeveloperAuth.on_mount(:mount_current_developer, %{}, session, %LiveView.Socket{})

      assert updated_socket.assigns.current_developer.developer.id == developer.id
    end

    test "assigns nil to current_developer assign if there isn't a valid developer_token", %{
      conn: conn
    } do
      developer_token = "invalid_token"
      session = conn |> put_session(:developer_token, developer_token) |> get_session()

      {:cont, updated_socket} =
        DeveloperAuth.on_mount(:mount_current_developer, %{}, session, %LiveView.Socket{})

      assert updated_socket.assigns.current_developer == nil
    end

    test "assigns nil to current_developer assign if there isn't a developer_token", %{conn: conn} do
      session = conn |> get_session()

      {:cont, updated_socket} =
        DeveloperAuth.on_mount(:mount_current_developer, %{}, session, %LiveView.Socket{})

      assert updated_socket.assigns.current_developer == nil
    end
  end

  describe "on_mount :require_authenticated" do
    test "authenticates current_developer based on a valid developer_token", %{
      conn: conn,
      developer: developer
    } do
      developer_token = Platform.generate_developer_session_token(developer)
      session = conn |> put_session(:developer_token, developer_token) |> get_session()

      {:cont, updated_socket} =
        DeveloperAuth.on_mount(:require_authenticated, %{}, session, %LiveView.Socket{})

      assert updated_socket.assigns.current_developer.developer.id == developer.id
    end

    test "redirects to login page if there isn't a valid developer_token", %{conn: conn} do
      developer_token = "invalid_token"
      session = conn |> put_session(:developer_token, developer_token) |> get_session()

      socket = %LiveView.Socket{
        endpoint: AntPressWeb.Endpoint,
        assigns: %{__changed__: %{}, flash: %{}}
      }

      {:halt, updated_socket} =
        DeveloperAuth.on_mount(:require_authenticated, %{}, session, socket)

      assert updated_socket.assigns.current_developer == nil
    end

    test "redirects to login page if there isn't a developer_token", %{conn: conn} do
      session = conn |> get_session()

      socket = %LiveView.Socket{
        endpoint: AntPressWeb.Endpoint,
        assigns: %{__changed__: %{}, flash: %{}}
      }

      {:halt, updated_socket} =
        DeveloperAuth.on_mount(:require_authenticated, %{}, session, socket)

      assert updated_socket.assigns.current_developer == nil
    end
  end

  describe "on_mount :require_sudo_mode" do
    test "allows developers that have authenticated in the last 10 minutes", %{
      conn: conn,
      developer: developer
    } do
      developer_token = Platform.generate_developer_session_token(developer)
      session = conn |> put_session(:developer_token, developer_token) |> get_session()

      socket = %LiveView.Socket{
        endpoint: AntPressWeb.Endpoint,
        assigns: %{__changed__: %{}, flash: %{}}
      }

      assert {:cont, _updated_socket} =
               DeveloperAuth.on_mount(:require_sudo_mode, %{}, session, socket)
    end

    test "redirects when authentication is too old", %{conn: conn, developer: developer} do
      eleven_minutes_ago = DateTime.utc_now(:second) |> DateTime.add(-11, :minute)
      developer = %{developer | authenticated_at: eleven_minutes_ago}
      developer_token = Platform.generate_developer_session_token(developer)
      {developer, token_inserted_at} = Platform.get_developer_by_session_token(developer_token)
      assert DateTime.compare(token_inserted_at, developer.authenticated_at) == :gt
      session = conn |> put_session(:developer_token, developer_token) |> get_session()

      socket = %LiveView.Socket{
        endpoint: AntPressWeb.Endpoint,
        assigns: %{__changed__: %{}, flash: %{}}
      }

      assert {:halt, _updated_socket} =
               DeveloperAuth.on_mount(:require_sudo_mode, %{}, session, socket)
    end
  end

  describe "require_authenticated_developer/2" do
    setup %{conn: conn} do
      %{conn: DeveloperAuth.fetch_current_developer_for_developer(conn, [])}
    end

    test "redirects if developer is not authenticated", %{conn: conn} do
      conn = conn |> fetch_flash() |> DeveloperAuth.require_authenticated_developer([])
      assert conn.halted

      assert redirected_to(conn) == ~p"/developers/log-in"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "このページを表示するにはログインが必要です"
    end

    test "stores the path to redirect to on GET", %{conn: conn} do
      halted_conn =
        %{conn | path_info: ["foo"], query_string: ""}
        |> fetch_flash()
        |> DeveloperAuth.require_authenticated_developer([])

      assert halted_conn.halted
      assert get_session(halted_conn, :developer_return_to) == "/foo"

      halted_conn =
        %{conn | path_info: ["foo"], query_string: "bar=baz"}
        |> fetch_flash()
        |> DeveloperAuth.require_authenticated_developer([])

      assert halted_conn.halted
      assert get_session(halted_conn, :developer_return_to) == "/foo?bar=baz"

      halted_conn =
        %{conn | path_info: ["foo"], query_string: "bar", method: "POST"}
        |> fetch_flash()
        |> DeveloperAuth.require_authenticated_developer([])

      assert halted_conn.halted
      refute get_session(halted_conn, :developer_return_to)
    end

    test "does not redirect if developer is authenticated", %{conn: conn, developer: developer} do
      conn =
        conn
        |> assign(:current_developer, Scope.for_developer(developer))
        |> DeveloperAuth.require_authenticated_developer([])

      refute conn.halted
      refute conn.status
    end
  end

  describe "disconnect_sessions/1" do
    test "broadcasts disconnect messages for each token" do
      tokens = [%{token: "token1"}, %{token: "token2"}]

      for %{token: token} <- tokens do
        AntPressWeb.Endpoint.subscribe("developers_sessions:#{Base.url_encode64(token)}")
      end

      DeveloperAuth.disconnect_sessions(tokens)

      assert_receive %Phoenix.Socket.Broadcast{
        event: "disconnect",
        topic: "developers_sessions:dG9rZW4x"
      }

      assert_receive %Phoenix.Socket.Broadcast{
        event: "disconnect",
        topic: "developers_sessions:dG9rZW4y"
      }
    end
  end
end
