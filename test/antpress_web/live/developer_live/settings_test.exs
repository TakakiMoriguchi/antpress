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

      assert html =~ "Change Email"
      assert html =~ "Save Password"
    end

    test "redirects if developer is not logged in", %{conn: conn} do
      assert {:error, redirect} = live(conn, ~p"/developers/settings")

      assert {:redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/developers/log-in"
      assert %{"error" => "You must log in to access this page."} = flash
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

  describe "update email form" do
    setup %{conn: conn} do
      developer = developer_fixture()
      %{conn: log_in_developer(conn, developer), developer: developer}
    end

    test "updates the developer email", %{conn: conn, developer: developer} do
      new_email = unique_developer_email()

      {:ok, lv, _html} = live(conn, ~p"/developers/settings")

      result =
        lv
        |> form("#email_form", %{
          "developer" => %{"email" => new_email}
        })
        |> render_submit()

      assert result =~ "A link to confirm your email"
      assert Platform.get_developer_by_email(developer.email)
    end

    test "renders errors with invalid data (phx-change)", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/developers/settings")

      result =
        lv
        |> element("#email_form")
        |> render_change(%{
          "action" => "update_email",
          "developer" => %{"email" => "with spaces"}
        })

      assert result =~ "Change Email"
      assert result =~ "must have the @ sign and no spaces"
    end

    test "renders errors with invalid data (phx-submit)", %{conn: conn, developer: developer} do
      {:ok, lv, _html} = live(conn, ~p"/developers/settings")

      result =
        lv
        |> form("#email_form", %{
          "developer" => %{"email" => developer.email}
        })
        |> render_submit()

      assert result =~ "Change Email"
      assert result =~ "did not change"
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
               "Password updated successfully"

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

      assert result =~ "Save Password"
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

      assert result =~ "Save Password"
      assert result =~ "should be at least 12 character(s)"
      assert result =~ "does not match password"
    end
  end

  describe "confirm email" do
    setup %{conn: conn} do
      developer = developer_fixture()
      email = unique_developer_email()

      token =
        extract_developer_token(fn url ->
          Platform.deliver_developer_update_email_instructions(
            %{developer | email: email},
            developer.email,
            url
          )
        end)

      %{conn: log_in_developer(conn, developer), token: token, email: email, developer: developer}
    end

    test "updates the developer email once", %{
      conn: conn,
      developer: developer,
      token: token,
      email: email
    } do
      {:error, redirect} = live(conn, ~p"/developers/settings/confirm-email/#{token}")

      assert {:live_redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/developers/settings"
      assert %{"info" => message} = flash
      assert message == "Email changed successfully."
      refute Platform.get_developer_by_email(developer.email)
      assert Platform.get_developer_by_email(email)

      # use confirm token again
      {:error, redirect} = live(conn, ~p"/developers/settings/confirm-email/#{token}")
      assert {:live_redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/developers/settings"
      assert %{"error" => message} = flash
      assert message == "Email change link is invalid or it has expired."
    end

    test "does not update email with invalid token", %{conn: conn, developer: developer} do
      {:error, redirect} = live(conn, ~p"/developers/settings/confirm-email/oops")
      assert {:live_redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/developers/settings"
      assert %{"error" => message} = flash
      assert message == "Email change link is invalid or it has expired."
      assert Platform.get_developer_by_email(developer.email)
    end

    test "redirects if developer is not logged in", %{token: token} do
      conn = build_conn()
      {:error, redirect} = live(conn, ~p"/developers/settings/confirm-email/#{token}")
      assert {:redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/developers/log-in"
      assert %{"error" => message} = flash
      assert message == "You must log in to access this page."
    end
  end
end
