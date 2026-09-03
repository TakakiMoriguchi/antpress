defmodule AntPressWeb.Router do
  use AntPressWeb, :router

  import AntPressWeb.DeveloperAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {AntPressWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_developer_for_developer
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", AntPressWeb do
    pipe_through :browser

    get "/", PageController, :home
  end

  # Other scopes may use custom stacks.
  # scope "/api", AntPressWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:antpress, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: AntPressWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  ## Authentication routes

  scope "/", AntPressWeb do
    pipe_through [:browser, :require_authenticated_developer]

    live_session :require_authenticated_developer,
      on_mount: [{AntPressWeb.DeveloperAuth, :require_authenticated}] do
      live "/developers/settings", DeveloperLive.Settings, :edit
      live "/developers/settings/confirm-email/:token", DeveloperLive.Settings, :confirm_email
    end

    post "/developers/update-password", DeveloperSessionController, :update_password
  end

  scope "/", AntPressWeb do
    pipe_through [:browser]

    live_session :current_developer,
      on_mount: [{AntPressWeb.DeveloperAuth, :mount_current_developer}] do
      live "/developers/log-in", DeveloperLive.Login, :new
      live "/developers/log-in/:token", DeveloperLive.Confirmation, :new
    end

    post "/developers/log-in", DeveloperSessionController, :create
    delete "/developers/log-out", DeveloperSessionController, :delete
  end
end
