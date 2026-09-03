defmodule AntPressWeb.PageController do
  use AntPressWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
