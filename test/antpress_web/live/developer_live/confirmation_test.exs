defmodule AntPressWeb.DeveloperLive.ConfirmationTest do
  use AntPressWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import AntPress.PlatformFixtures

  alias AntPress.Platform

  setup do
    %{
      unconfirmed_developer: unconfirmed_developer_fixture(),
      confirmed_developer: developer_fixture()
    }
  end

  describe "Confirm developer" do
    test "renders confirmation page for unconfirmed developer", %{
      conn: conn,
      unconfirmed_developer: developer
    } do
      token =
        extract_developer_token(fn url ->
          Platform.deliver_login_instructions(developer, url)
        end)

      {:ok, _lv, html} = live(conn, ~p"/developers/log-in/#{token}")
      assert html =~ "Confirm and stay logged in"
    end

    test "renders login page for confirmed developer", %{
      conn: conn,
      confirmed_developer: developer
    } do
      token =
        extract_developer_token(fn url ->
          Platform.deliver_login_instructions(developer, url)
        end)

      {:ok, _lv, html} = live(conn, ~p"/developers/log-in/#{token}")
      refute html =~ "Confirm my account"
      assert html =~ "Keep me logged in on this device"
    end

    test "renders login page for already logged in developer", %{
      conn: conn,
      confirmed_developer: developer
    } do
      conn = log_in_developer(conn, developer)

      token =
        extract_developer_token(fn url ->
          Platform.deliver_login_instructions(developer, url)
        end)

      {:ok, _lv, html} = live(conn, ~p"/developers/log-in/#{token}")
      refute html =~ "Confirm my account"
      assert html =~ "Log in"
    end

    test "confirms the given token once", %{conn: conn, unconfirmed_developer: developer} do
      token =
        extract_developer_token(fn url ->
          Platform.deliver_login_instructions(developer, url)
        end)

      {:ok, lv, _html} = live(conn, ~p"/developers/log-in/#{token}")

      form = form(lv, "#confirmation_form", %{"developer" => %{"token" => token}})
      render_submit(form)

      conn = follow_trigger_action(form, conn)

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~
               "Developer confirmed successfully"

      assert Platform.get_developer!(developer.id).confirmed_at
      # we are logged in now
      assert get_session(conn, :developer_token)
      assert redirected_to(conn) == ~p"/clients"

      # log out, new conn
      conn = build_conn()

      {:ok, _lv, html} =
        live(conn, ~p"/developers/log-in/#{token}")
        |> follow_redirect(conn, ~p"/developers/log-in")

      assert html =~ "Magic link is invalid or it has expired"
    end

    test "logs confirmed developer in without changing confirmed_at", %{
      conn: conn,
      confirmed_developer: developer
    } do
      token =
        extract_developer_token(fn url ->
          Platform.deliver_login_instructions(developer, url)
        end)

      {:ok, lv, _html} = live(conn, ~p"/developers/log-in/#{token}")

      form = form(lv, "#login_form", %{"developer" => %{"token" => token}})
      render_submit(form)

      conn = follow_trigger_action(form, conn)

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~
               "Welcome back!"

      assert Platform.get_developer!(developer.id).confirmed_at == developer.confirmed_at

      # log out, new conn
      conn = build_conn()

      {:ok, _lv, html} =
        live(conn, ~p"/developers/log-in/#{token}")
        |> follow_redirect(conn, ~p"/developers/log-in")

      assert html =~ "Magic link is invalid or it has expired"
    end

    test "raises error for invalid token", %{conn: conn} do
      {:ok, _lv, html} =
        live(conn, ~p"/developers/log-in/invalid-token")
        |> follow_redirect(conn, ~p"/developers/log-in")

      assert html =~ "Magic link is invalid or it has expired"
    end
  end
end
