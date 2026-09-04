defmodule AntPressWeb.DeveloperLive.SettingsTest do
  use AntPressWeb.ConnCase, async: true

  alias AntPress.Platform
  import Phoenix.LiveViewTest
  import AntPress.PlatformFixtures

  describe "Settings page" do
    test "renders settings page", %{conn: conn} do
      {:ok, _lv, html} =
        conn
        |> log_in_developer(developer_fixture())
        |> live(~p"/developers/settings")

      assert html =~ "アカウント設定"
      assert html =~ "表示テーマ"
      assert html =~ "屋号"
      assert html =~ "メールアドレス"
      assert html =~ "パスワードを変更"
      # メールアドレスと屋号は変更不可（表示のみ）。
      # パスワードフォームは hidden でメールを送る（パスワードマネージャ向け）ので、
      # 編集可能な入力欄がないことで確認する
      refute html =~ ~s(name="developer[email]" type="email")
      refute html =~ ~s(name="developer[name]")
      refute html =~ "email_form"
      refute html =~ "profile_form"
    end

    test "redirects if developer is not logged in", %{conn: conn} do
      assert {:error, redirect} = live(conn, ~p"/developers/settings")

      assert {:redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/developers/log-in"
      assert %{"error" => "このページを表示するにはログインが必要です"} = flash
    end

    test "redirects if developer is not in sudo mode", %{conn: conn} do
      {:ok, conn} =
        conn
        |> log_in_developer(developer_fixture(),
          token_authenticated_at: DateTime.add(DateTime.utc_now(:second), -11, :minute)
        )
        |> live(~p"/developers/settings")
        |> follow_redirect(conn, ~p"/developers/log-in")

      assert conn.resp_body =~ "You must re-authenticate to access this page."
    end
  end

  describe "update password form" do
    setup %{conn: conn} do
      developer = developer_fixture()
      %{conn: log_in_developer(conn, developer), developer: developer}
    end

    test "updates the developer password", %{conn: conn, developer: developer} do
      new_password = valid_developer_password()

      {:ok, lv, _html} = live(conn, ~p"/developers/settings")

      form =
        form(lv, "#password_form", %{
          "developer" => %{
            "email" => developer.email,
            "password" => new_password,
            "password_confirmation" => new_password
          }
        })

      render_submit(form)

      new_password_conn = follow_trigger_action(form, conn)

      assert redirected_to(new_password_conn) == ~p"/developers/settings"

      assert get_session(new_password_conn, :developer_token) !=
               get_session(conn, :developer_token)

      assert Phoenix.Flash.get(new_password_conn.assigns.flash, :info) =~
               "パスワードを変更しました"

      assert Platform.get_developer_by_email_and_password(developer.email, new_password)
    end

    test "renders errors with invalid data (phx-change)", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/developers/settings")

      result =
        lv
        |> element("#password_form")
        |> render_change(%{
          "developer" => %{
            "password" => "too short",
            "password_confirmation" => "does not match"
          }
        })

      assert result =~ "パスワードを変更"
      assert result =~ "should be at least 12 character(s)"
      assert result =~ "does not match password"
    end

    test "renders errors with invalid data (phx-submit)", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/developers/settings")

      result =
        lv
        |> form("#password_form", %{
          "developer" => %{
            "password" => "too short",
            "password_confirmation" => "does not match"
          }
        })
        |> render_submit()

      assert result =~ "パスワードを変更"
      assert result =~ "should be at least 12 character(s)"
      assert result =~ "does not match password"
    end
  end
end
