defmodule AntPressWeb.DeveloperSessionController do
  use AntPressWeb, :controller

  alias AntPress.Platform
  alias AntPressWeb.DeveloperAuth

  def create(conn, %{"_action" => "confirmed"} = params) do
    create(conn, params, "Developer confirmed successfully.")
  end

  def create(conn, params) do
    create(conn, params, "Welcome back!")
  end

  # magic link login
  defp create(conn, %{"developer" => %{"token" => token} = developer_params}, info) do
    case Platform.login_developer_by_magic_link(token) do
      {:ok, {developer, tokens_to_disconnect}} ->
        DeveloperAuth.disconnect_sessions(tokens_to_disconnect)

        conn
        |> put_flash(:info, info)
        |> DeveloperAuth.log_in_developer(developer, developer_params)

      _ ->
        conn
        |> put_flash(:error, "The link is invalid or it has expired.")
        |> redirect(to: ~p"/developers/log-in")
    end
  end

  # email + password login
  defp create(conn, %{"developer" => developer_params}, info) do
    %{"email" => email, "password" => password} = developer_params

    if developer = Platform.get_developer_by_email_and_password(email, password) do
      conn
      |> put_flash(:info, info)
      |> DeveloperAuth.log_in_developer(developer, developer_params)
    else
      # In order to prevent user enumeration attacks, don't disclose whether the email is registered.
      conn
      |> put_flash(:error, "Invalid email or password")
      |> put_flash(:email, String.slice(email, 0, 160))
      |> redirect(to: ~p"/developers/log-in")
    end
  end

  def update_password(conn, %{"developer" => developer_params} = params) do
    developer = conn.assigns.current_developer.developer
    true = Platform.sudo_mode?(developer)

    {:ok, {_developer, expired_tokens}} =
      Platform.update_developer_password(developer, developer_params)

    # disconnect all existing LiveViews with old sessions
    DeveloperAuth.disconnect_sessions(expired_tokens)

    conn
    |> put_session(:developer_return_to, ~p"/developers/settings")
    |> create(params, "Password updated successfully!")
  end

  def delete(conn, _params) do
    conn
    |> put_flash(:info, "Logged out successfully.")
    |> DeveloperAuth.log_out_developer()
  end
end
