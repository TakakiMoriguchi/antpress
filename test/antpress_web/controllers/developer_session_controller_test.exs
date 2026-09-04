defmodule AntPressWeb.DeveloperSessionControllerTest do
  use AntPressWeb.ConnCase, async: true

  import AntPress.PlatformFixtures
  alias AntPress.Platform

  setup do
    %{unconfirmed_developer: unconfirmed_developer_fixture(), developer: developer_fixture()}
  end

  describe "POST /developers/log-in - email and password" do
    test "logs the developer in", %{conn: conn, developer: developer} do
      developer = set_password(developer)

      conn =
        post(conn, ~p"/developers/log-in", %{
          "developer" => %{"email" => developer.email, "password" => valid_developer_password()}
        })

      assert get_session(conn, :developer_token)
      assert redirected_to(conn) == ~p"/clients"

      # Now do a logged in request and assert on the menu
      conn = get(conn, ~p"/")
      response = html_response(conn, 200)
      # ヘッダーは屋号を表示しない（→ root.html.heex）。
      # ログイン成功はリダイレクト先とナビの存在で確認する
      assert response =~ "クライアント"
      assert response =~ "ログアウト"
      assert response =~ ~p"/developers/settings"
      assert response =~ ~p"/developers/log-out"
    end

    test "logs the developer in with remember me", %{conn: conn, developer: developer} do
      developer = set_password(developer)

      conn =
        post(conn, ~p"/developers/log-in", %{
          "developer" => %{
            "email" => developer.email,
            "password" => valid_developer_password(),
            "remember_me" => "true"
          }
        })

      assert conn.resp_cookies["_ant_press_web_developer_remember_me"]
      assert redirected_to(conn) == ~p"/clients"
    end

    test "logs the developer in with return to", %{conn: conn, developer: developer} do
      developer = set_password(developer)

      conn =
        conn
        |> init_test_session(developer_return_to: "/foo/bar")
        |> post(~p"/developers/log-in", %{
          "developer" => %{
            "email" => developer.email,
            "password" => valid_developer_password()
          }
        })

      assert redirected_to(conn) == "/foo/bar"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Welcome back!"
    end

    test "redirects to login page with invalid credentials", %{conn: conn, developer: developer} do
      conn =
        post(conn, ~p"/developers/log-in?mode=password", %{
          "developer" => %{"email" => developer.email, "password" => "invalid_password"}
        })

      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Invalid email or password"
      assert redirected_to(conn) == ~p"/developers/log-in"
    end
  end

  describe "POST /developers/log-in - magic link" do
    test "logs the developer in", %{conn: conn, developer: developer} do
      {token, _hashed_token} = generate_developer_magic_link_token(developer)

      conn =
        post(conn, ~p"/developers/log-in", %{
          "developer" => %{"token" => token}
        })

      assert get_session(conn, :developer_token)
      assert redirected_to(conn) == ~p"/clients"

      # Now do a logged in request and assert on the menu
      conn = get(conn, ~p"/")
      response = html_response(conn, 200)
      # ヘッダーは屋号を表示しない（→ root.html.heex）。
      # ログイン成功はリダイレクト先とナビの存在で確認する
      assert response =~ "クライアント"
      assert response =~ "ログアウト"
      assert response =~ ~p"/developers/settings"
      assert response =~ ~p"/developers/log-out"
    end

    test "confirms unconfirmed developer", %{conn: conn, unconfirmed_developer: developer} do
      {token, _hashed_token} = generate_developer_magic_link_token(developer)
      refute developer.confirmed_at

      conn =
        post(conn, ~p"/developers/log-in", %{
          "developer" => %{"token" => token},
          "_action" => "confirmed"
        })

      assert get_session(conn, :developer_token)
      assert redirected_to(conn) == ~p"/clients"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Developer confirmed successfully."

      assert Platform.get_developer!(developer.id).confirmed_at

      # Now do a logged in request and assert on the menu
      conn = get(conn, ~p"/")
      response = html_response(conn, 200)
      # ヘッダーは屋号を表示しない（→ root.html.heex）。
      # ログイン成功はリダイレクト先とナビの存在で確認する
      assert response =~ "クライアント"
      assert response =~ "ログアウト"
      assert response =~ ~p"/developers/settings"
      assert response =~ ~p"/developers/log-out"
    end

    test "redirects to login page when magic link is invalid", %{conn: conn} do
      conn =
        post(conn, ~p"/developers/log-in", %{
          "developer" => %{"token" => "invalid"}
        })

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "The link is invalid or it has expired."

      assert redirected_to(conn) == ~p"/developers/log-in"
    end
  end

  describe "DELETE /developers/log-out" do
    test "logs the developer out", %{conn: conn, developer: developer} do
      conn = conn |> log_in_developer(developer) |> delete(~p"/developers/log-out")
      assert redirected_to(conn) == ~p"/"
      refute get_session(conn, :developer_token)
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Logged out successfully"
    end

    test "succeeds even if the developer is not logged in", %{conn: conn} do
      conn = delete(conn, ~p"/developers/log-out")
      assert redirected_to(conn) == ~p"/"
      refute get_session(conn, :developer_token)
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Logged out successfully"
    end
  end
end
