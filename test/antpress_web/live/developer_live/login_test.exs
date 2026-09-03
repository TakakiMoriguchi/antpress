defmodule AntPressWeb.DeveloperLive.LoginTest do
  use AntPressWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import AntPress.PlatformFixtures

  describe "login page" do
    test "renders login page", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/developers/log-in")

      assert html =~ "antpress にログイン"
      assert html =~ "Log in with email"
      # セルフサインアップは提供しない（→ docs/DECISIONS.md 1.3）
      refute html =~ "Sign up"
      refute html =~ "/developers/register"
    end
  end

  describe "developer login - magic link" do
    test "sends magic link email when developer exists", %{conn: conn} do
      developer = developer_fixture()

      {:ok, lv, _html} = live(conn, ~p"/developers/log-in")

      {:ok, _lv, html} =
        form(lv, "#login_form_magic", developer: %{email: developer.email})
        |> render_submit()
        |> follow_redirect(conn, ~p"/developers/log-in")

      assert html =~ "If your email is in our system"

      assert AntPress.Repo.get_by!(AntPress.Platform.DeveloperToken, developer_id: developer.id).context ==
               "login"
    end

    test "does not disclose if developer is registered", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/developers/log-in")

      {:ok, _lv, html} =
        form(lv, "#login_form_magic", developer: %{email: "idonotexist@example.com"})
        |> render_submit()
        |> follow_redirect(conn, ~p"/developers/log-in")

      assert html =~ "If your email is in our system"
    end
  end

  describe "developer login - password" do
    test "redirects if developer logs in with valid credentials", %{conn: conn} do
      developer = developer_fixture() |> set_password()

      {:ok, lv, _html} = live(conn, ~p"/developers/log-in")

      form =
        form(lv, "#login_form_password",
          developer: %{
            email: developer.email,
            password: valid_developer_password(),
            remember_me: true
          }
        )

      conn = submit_form(form, conn)

      assert redirected_to(conn) == ~p"/"
    end

    test "redirects to login page with a flash error if credentials are invalid", %{
      conn: conn
    } do
      {:ok, lv, _html} = live(conn, ~p"/developers/log-in")

      form =
        form(lv, "#login_form_password",
          developer: %{email: "test@email.com", password: "123456"}
        )

      render_submit(form, %{user: %{remember_me: true}})

      conn = follow_trigger_action(form, conn)
      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Invalid email or password"
      assert redirected_to(conn) == ~p"/developers/log-in"
    end
  end

  describe "re-authentication (sudo mode)" do
    setup %{conn: conn} do
      developer = developer_fixture()
      %{developer: developer, conn: log_in_developer(conn, developer)}
    end

    test "shows login page with email filled in", %{conn: conn, developer: developer} do
      {:ok, _lv, html} = live(conn, ~p"/developers/log-in")

      assert html =~ "再認証が必要です"
      refute html =~ "Register"
      assert html =~ "Log in with email"

      assert html =~
               ~s(<input type="email" name="developer[email]" id="login_form_magic_email" value="#{developer.email}")
    end
  end
end
